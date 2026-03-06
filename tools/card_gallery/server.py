from __future__ import annotations

import json
import mimetypes
import re
import secrets
import os
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from comfyui import (
    ComfyUiError,
    download_image_bytes,
    get_first_image_ref,
    inject_into_workflow,
    load_workflow,
    submit_and_wait,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
WEB_ROOT = Path(__file__).resolve().parent / "web"

FRAME_PATH = REPO_ROOT / "design" / "frame_bureaucracy.json"
CARDS_PATH = REPO_ROOT / "design" / "cards_bureaucracy.json"
BACKUP_DIR = REPO_ROOT / "design" / "backups"

WORKFLOW_PATH = REPO_ROOT / "tools" / "comfyui" / "workflows" / "card_art_inner.json"

DEFAULT_PORT = 8787
DEFAULT_COMFYUI_URL = "http://127.0.0.1:8188"
DEFAULT_ART_WIDTH = 1024
DEFAULT_ART_HEIGHT = 688
DEFAULT_COMFYUI_JOB_TIMEOUT_S = 1800.0  # 30 minutes


_write_lock = threading.Lock()


def _json_read(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _json_write(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    tmp.replace(path)


def _backup_cards() -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    backup_path = BACKUP_DIR / f"cards_bureaucracy.{ts}.json"
    if CARDS_PATH.exists():
        backup_path.write_text(CARDS_PATH.read_text(encoding="utf-8"), encoding="utf-8")


def _safe_path_from_url(url_path: str) -> Path | None:
    """Map a URL like /art/foo.png to a repo file path.

    Prevents path traversal.
    """
    if url_path.startswith("/"):
        url_path = url_path[1:]
    # Only serve specific top-level folders.
    allowed = ("art/", "design/", "output/")
    if not any(url_path.startswith(a) for a in allowed):
        return None

    fs_path = (REPO_ROOT / url_path).resolve()
    try:
        fs_path.relative_to(REPO_ROOT)
    except Exception:
        return None

    return fs_path


class Handler(BaseHTTPRequestHandler):
    server_version = "card-gallery/0.1"

    def _send_json(self, status: int, payload: Any) -> None:
        raw = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _send_text(self, status: int, text: str, content_type: str = "text/plain; charset=utf-8") -> None:
        raw = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _read_json_body(self) -> Any:
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""
        try:
            return json.loads(body.decode("utf-8"))
        except Exception:
            raise ValueError("Invalid JSON body")

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/" or self.path.startswith("/?"):
            return self._serve_web_file(WEB_ROOT / "index.html")

        if self.path == "/api/frame":
            if not FRAME_PATH.exists():
                return self._send_json(HTTPStatus.NOT_FOUND, {"error": "Missing design/frame_bureaucracy.json"})
            return self._send_json(HTTPStatus.OK, _json_read(FRAME_PATH))

        if self.path == "/api/cards":
            if not CARDS_PATH.exists():
                return self._send_json(HTTPStatus.NOT_FOUND, {"error": "Missing design/cards_bureaucracy.json"})
            return self._send_json(HTTPStatus.OK, _json_read(CARDS_PATH))

        if self.path.startswith("/web/"):
            rel = self.path.removeprefix("/web/")
            return self._serve_web_file(WEB_ROOT / rel)

        fs_path = _safe_path_from_url(self.path)
        if fs_path is not None:
            return self._serve_repo_file(fs_path)

        return self._send_text(HTTPStatus.NOT_FOUND, "Not Found")

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/api/cards":
            try:
                body = self._read_json_body()
            except ValueError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})

            with _write_lock:
                _backup_cards()
                _json_write(CARDS_PATH, body)

            return self._send_json(HTTPStatus.OK, {"ok": True})

        if self.path == "/api/generate":
            try:
                body = self._read_json_body()
            except ValueError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})

            card_id = body.get("card_id")
            count = body.get("count", 4)
            try:
                count = int(count)
            except Exception:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": "count must be an integer"})

            if not isinstance(card_id, str) or not card_id:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": "card_id is required"})

            try:
                updated = self._generate_variants(card_id=card_id, count=count)
            except ComfyUiError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
            except Exception as e:  # noqa: BLE001
                return self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Unexpected error: {e}"})

            return self._send_json(HTTPStatus.OK, updated)


        if self.path == "/api/promote":
            try:
                body = self._read_json_body()
            except ValueError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})

            card_id = body.get("card_id")
            if not isinstance(card_id, str) or not card_id:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": "card_id is required"})

            try:
                updated = self._promote_card(card_id=card_id)
            except ValueError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
            except Exception as e:  # noqa: BLE001
                return self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Unexpected error: {e}"})

            return self._send_json(HTTPStatus.OK, updated)

        if self.path == "/api/upload_art":
            try:
                updated = self._upload_art()
            except ValueError as e:
                return self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
            except Exception as e:  # noqa: BLE001
                return self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Unexpected error: {e}"})

            return self._send_json(HTTPStatus.OK, updated)

        return self._send_text(HTTPStatus.NOT_FOUND, "Not Found")

    def _serve_web_file(self, path: Path) -> None:
        if not path.exists() or not path.is_file():
            return self._send_text(HTTPStatus.NOT_FOUND, "Not Found")
        return self._serve_file(path)

    def _serve_repo_file(self, path: Path) -> None:
        if not path.exists() or not path.is_file():
            return self._send_text(HTTPStatus.NOT_FOUND, "Not Found")
        return self._serve_file(path)

    def _serve_file(self, path: Path) -> None:
        ctype, _ = mimetypes.guess_type(str(path))
        if not ctype:
            ctype = "application/octet-stream"
        raw = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        # Disable caching for rapid iteration
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _upload_art(self) -> dict[str, Any]:
        ctype = self.headers.get("Content-Type") or ""
        if "multipart/form-data" not in ctype:
            raise ValueError("Expected multipart/form-data")

        boundary = None
        for part in ctype.split(";"):
            part = part.strip()
            if part.lower().startswith("boundary="):
                boundary = part.split("=", 1)[1].strip().strip('"')
                break
        if not boundary:
            raise ValueError("Missing multipart boundary")

        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            raise ValueError("Missing request body")

        body = self.rfile.read(length)
        delim = ("--" + boundary).encode("utf-8")

        fields: dict[str, str] = {}
        files: dict[str, dict[str, object]] = {}

        chunks = body.split(delim)
        for chunk in chunks:
            if not chunk:
                continue
            if chunk.startswith(b"--"):
                # final boundary
                continue
            if chunk.startswith(b"\r\n"):
                chunk = chunk[2:]
            if chunk.endswith(b"\r\n"):
                chunk = chunk[:-2]

            header_blob, sep, data = chunk.partition(b"\r\n\r\n")
            if not sep:
                continue

            header_lines = header_blob.decode("utf-8", errors="replace").split("\r\n")
            headers: dict[str, str] = {}
            for line in header_lines:
                if ":" not in line:
                    continue
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

            disp = headers.get("content-disposition", "")
            if not disp.lower().startswith("form-data"):
                continue

            name = None
            filename = None
            for seg in disp.split(";"):
                seg = seg.strip()
                if seg.startswith("name="):
                    name = seg.split("=", 1)[1].strip().strip('"')
                elif seg.startswith("filename="):
                    filename = seg.split("=", 1)[1].strip().strip('"')

            if not name:
                continue

            if filename is None:
                fields[name] = data.decode("utf-8", errors="replace").strip()
            else:
                files[name] = {"filename": filename, "data": data}

        card_id = (fields.get("card_id") or "").strip()
        if not card_id:
            raise ValueError("card_id is required")

        file_info = files.get("file")
        if not isinstance(file_info, dict):
            raise ValueError("file is required")

        filename = str(file_info.get("filename") or "")
        data = file_info.get("data")
        if not isinstance(data, (bytes, bytearray)) or not data:
            raise ValueError("Uploaded file is empty")

        ext = os.path.splitext(filename)[1].lower()
        if ext not in (".png", ".jpg", ".jpeg", ".webp"):
            ext = ".png"

        stem = os.path.splitext(os.path.basename(filename))[0] or "manual"
        stem = re.sub(r"[^a-zA-Z0-9_-]+", "_", stem).strip("_")[:60] or "manual"

        out_dir = REPO_ROOT / "art" / "generated" / "card_art" / card_id
        out_dir.mkdir(parents=True, exist_ok=True)

        ts = time.strftime("%Y%m%d-%H%M%S")
        nonce = secrets.token_hex(3)
        out_path = out_dir / f"{card_id}_{stem}_{ts}_{nonce}{ext}"
        out_path.write_bytes(bytes(data))

        with _write_lock:
            cards_doc = _json_read(CARDS_PATH)

            cards = cards_doc.get("cards")
            if not isinstance(cards, list):
                raise ValueError("design/cards_bureaucracy.json missing cards[]")

            card = next((c for c in cards if isinstance(c, dict) and c.get("id") == card_id), None)
            if not isinstance(card, dict):
                raise ValueError(f"Card not found: {card_id}")

            variants = card.get("variants")
            if not isinstance(variants, list):
                variants = []
                card["variants"] = variants

            existing_seeds = {v.get("seed") for v in variants if isinstance(v, dict)}
            seed = secrets.randbelow(2_000_000_000)
            while seed in existing_seeds:
                seed = secrets.randbelow(2_000_000_000)

            variants.append(
                {
                    "seed": seed,
                    "file": str(out_path.relative_to(REPO_ROOT)).replace("\\", "/"),
                    "source": "comfyui",
                    "prompt_id": prompt_id,
                    "positive_prompt": positive_prompt,
                    "negative_prompt": negative_prompt,
                    "width": art_width,
                    "height": art_height,
                    "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                }
            )
            card["selected_seed"] = seed

            _backup_cards()
            _json_write(CARDS_PATH, cards_doc)

        return cards_doc
    def _generate_variants(self, *, card_id: str, count: int) -> dict[str, Any]:
        if count < 1 or count > 20:
            raise ComfyUiError("count must be between 1 and 20")

        if not WORKFLOW_PATH.exists():
            raise ComfyUiError(
                f"Missing workflow at {WORKFLOW_PATH}. Export your ComfyUI API workflow JSON there (or edit it)."
            )

        comfyui_url = os.environ.get("COMFYUI_URL") or DEFAULT_COMFYUI_URL

        with _write_lock:
            cards_doc = _json_read(CARDS_PATH)

        cards = cards_doc.get("cards")
        if not isinstance(cards, list):
            raise ComfyUiError("design/cards_bureaucracy.json missing cards[]")

        card = next((c for c in cards if isinstance(c, dict) and c.get("id") == card_id), None)
        if not isinstance(card, dict):
            raise ComfyUiError(f"Card not found: {card_id}")

        prompt = card.get("art_prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            raise ComfyUiError("Card has no art_prompt")

        negative = card.get("negative_prompt")
        if negative is None:
            negative = cards_doc.get("negative_prompt_default")
        if not isinstance(negative, str):
            negative = None

        # Optional "house style" prompt wrapper (see tools/comfyui/workflows/prompt-builder.jsx)
        use_house_style = card.get("use_house_style")
        if not isinstance(use_house_style, bool):
            use_house_style = True

        house_pos = cards_doc.get("house_style_positive_default")
        if not isinstance(house_pos, str):
            house_pos = ""

        house_neg = cards_doc.get("house_style_negative_default")
        if not isinstance(house_neg, str):
            house_neg = ""

        color_suffix = cards_doc.get("color_accent_suffix_default")
        if not isinstance(color_suffix, str) or not color_suffix.strip():
            color_suffix = "used sparingly as a graphic highlight against neutral tones"

        color_accent = card.get("color_accent")
        if not isinstance(color_accent, str):
            color_accent = ""

        positive_parts: list[str] = []
        if use_house_style and house_pos.strip():
            positive_parts.append(house_pos.strip())
        if use_house_style and color_accent.strip():
            positive_parts.append(f"{color_accent.strip()} accent color {color_suffix.strip()}")
        positive_parts.append(prompt.strip())
        positive_prompt = ", ".join([p.strip().strip(",") for p in positive_parts if p and p.strip()])

        negative_parts: list[str] = []
        if use_house_style and house_neg.strip():
            negative_parts.append(house_neg.strip())
        if isinstance(negative, str) and negative.strip():
            negative_parts.append(negative.strip())
        negative_prompt = ", ".join([p.strip().strip(",") for p in negative_parts if p and p.strip()]) or None


        # Resolve output size (lets you use SDXL recommended dims like 1216x832)
        art_width = card.get("art_width")
        art_height = card.get("art_height")
        if not isinstance(art_width, int):
            art_width = cards_doc.get("art_width_default")
        if not isinstance(art_height, int):
            art_height = cards_doc.get("art_height_default")

        if not isinstance(art_width, int):
            art_width = DEFAULT_ART_WIDTH
        if not isinstance(art_height, int):
            art_height = DEFAULT_ART_HEIGHT

        if art_width < 256 or art_width > 2048 or art_height < 256 or art_height > 2048:
            raise ComfyUiError("art_width/art_height must be between 256 and 2048")
        variants = card.get("variants")
        if not isinstance(variants, list):
            variants = []
            card["variants"] = variants

        existing_seeds = {v.get("seed") for v in variants if isinstance(v, dict)}

        workflow = load_workflow(str(WORKFLOW_PATH))


        for _ in range(count):
            seed = secrets.randbelow(2_000_000_000)
            while seed in existing_seeds:
                seed = secrets.randbelow(2_000_000_000)

            existing_seeds.add(seed)

            filename_prefix = f"card_art/{card_id}/{card_id}_seed{seed}"
            injected = inject_into_workflow(
                workflow,
                positive_prompt=positive_prompt,
                negative_prompt=negative_prompt,
                seed=seed,
                width=art_width,
                height=art_height,
                filename_prefix=filename_prefix,
            )

            prompt_graph = injected.get("prompt") if isinstance(injected.get("prompt"), dict) else injected
            timeout_s = float(os.environ.get("COMFYUI_JOB_TIMEOUT_S") or DEFAULT_COMFYUI_JOB_TIMEOUT_S)
            prompt_id = submit_and_wait(comfyui_url, prompt_graph=prompt_graph, timeout_s=timeout_s)
            ref = get_first_image_ref(comfyui_url, prompt_id)
            img = download_image_bytes(comfyui_url, ref)

            out_dir = REPO_ROOT / "art" / "generated" / "card_art" / card_id
            out_dir.mkdir(parents=True, exist_ok=True)

            # Keep stable naming regardless of what ComfyUI calls it.
            out_path = out_dir / f"{card_id}_seed{seed}.png"
            out_path.write_bytes(img)

            variants.append(
                {
                    "seed": seed,
                    "file": str(out_path.relative_to(REPO_ROOT)).replace("\\", "/"),
                    "source": "comfyui",
                    "prompt_id": prompt_id,
                    "positive_prompt": positive_prompt,
                    "negative_prompt": negative_prompt,
                    "width": art_width,
                    "height": art_height,
                    "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                }
            )
            if card.get("selected_seed") in (None, ""):
                card["selected_seed"] = seed

        with _write_lock:
            _backup_cards()
            _json_write(CARDS_PATH, cards_doc)

        return cards_doc



    def _promote_card(self, *, card_id: str) -> dict[str, Any]:
        """Create a Godot Card resource + icon for the selected variant.

        Outputs (tracked):
        - art/promoted/card_icons/<card_id>.png
        - common_cards/promoted/<card_id>.tres

        Also marks the card entry in design/cards_bureaucracy.json with the output paths.
        """

        def esc(s: str) -> str:
            # Godot .tres string literal escaping.
            return (
                s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\r\n", "\\n")
                .replace("\n", "\\n")
                .replace("\r", "\\n")
            )

        with _write_lock:
            cards_doc = _json_read(CARDS_PATH)

            cards = cards_doc.get("cards")
            if not isinstance(cards, list):
                raise ValueError("design/cards_bureaucracy.json missing cards[]")

            card = next((c for c in cards if isinstance(c, dict) and c.get("id") == card_id), None)
            if not isinstance(card, dict):
                raise ValueError(f"Card not found: {card_id}")

            seed = card.get("selected_seed")
            if not isinstance(seed, int):
                raise ValueError("Select an art variant first (selected_seed is missing).")

            variants = card.get("variants")
            if not isinstance(variants, list):
                raise ValueError("Card has no variants list.")

            variant = next((v for v in variants if isinstance(v, dict) and v.get("seed") == seed), None)
            if not isinstance(variant, dict) or not isinstance(variant.get("file"), str):
                raise ValueError("Selected variant file not found.")

            src_rel = variant["file"].lstrip("/")
            src_path = (REPO_ROOT / src_rel).resolve()
            try:
                src_path.relative_to(REPO_ROOT)
            except Exception:
                raise ValueError("Invalid variant file path.")
            if not src_path.exists():
                raise ValueError(f"Variant image missing on disk: {src_rel}")

            # Output paths (tracked)
            icon_rel = f"art/promoted/card_icons/{card_id}.png"
            icon_path = (REPO_ROOT / icon_rel).resolve()
            icon_path.parent.mkdir(parents=True, exist_ok=True)
            icon_path.write_bytes(src_path.read_bytes())

            card_rel = f"common_cards/promoted/{card_id}.tres"
            card_path = (REPO_ROOT / card_rel).resolve()
            card_path.parent.mkdir(parents=True, exist_ok=True)

            type_map = {"ATTACK": 0, "SKILL": 1, "POWER": 2}
            rarity_map = {"COMMON": 0, "UNCOMMON": 1, "RARE": 2}
            target_map = {"SELF": 0, "SINGLE_ENEMY": 1, "ALL_ENEMIES": 2, "EVERYONE": 3}

            type_str = str(card.get("type") or "SKILL").upper()
            rarity_str = str(card.get("rarity") or "COMMON").upper()
            target_str = str(card.get("target") or "SELF").upper()

            if type_str not in type_map:
                raise ValueError(f"Unknown type: {type_str}")
            if rarity_str not in rarity_map:
                raise ValueError(f"Unknown rarity: {rarity_str}")
            if target_str not in target_map:
                raise ValueError(f"Unknown target: {target_str}")

            cost = card.get("cost")
            if not isinstance(cost, int):
                try:
                    cost = int(cost)
                except Exception:
                    cost = 1

            sound_by_type = {
                "ATTACK": "res://art/slash.ogg",
                "SKILL": "res://art/block.ogg",
                "POWER": "res://art/true_strength.ogg",
            }
            sound_path = sound_by_type.get(type_str, "res://art/block.ogg")

            name = str(card.get("name") or card_id)
            rules = str(card.get("rules_text") or "")
            tooltip = f"[center][b]{name}[/b]\\n{rules}[/center]"

            tres = "".join(
                [
                    '[gd_resource type="Resource" script_class="Card" load_steps=4 format=3]\n\n',
                    f'[ext_resource type="Texture2D" path="res://{icon_rel}" id="1_icon"]\n',
                    '[ext_resource type="Script" path="res://custom_resources/card.gd" id="2_script"]\n',
                    f'[ext_resource type="AudioStream" path="{sound_path}" id="3_sound"]\n\n',
                    '[resource]\n',
                    'script = ExtResource("2_script")\n',
                    f'id = "{esc(card_id)}"\n',
                    f'type = {type_map[type_str]}\n',
                    f'rarity = {rarity_map[rarity_str]}\n',
                    f'target = {target_map[target_str]}\n',
                    f'cost = {cost}\n',
                    'exhausts = false\n',
                    'icon = ExtResource("1_icon")\n',
                    f'tooltip_text = "{esc(tooltip)}"\n',
                    'sound = ExtResource("3_sound")\n',
                ]
            )

            card_path.write_text(tres, encoding="utf-8", newline="\n")

            # Mark in design JSON
            card["promoted"] = True
            card["godot_card_path"] = card_rel.replace("\\", "/")
            card["godot_icon_path"] = icon_rel.replace("\\", "/")
            card["promoted_seed"] = seed
            card["promoted_at"] = time.strftime("%Y-%m-%d %H:%M:%S")

            _backup_cards()
            _json_write(CARDS_PATH, cards_doc)

        return cards_doc
def main() -> None:
    mimetypes.add_type("image/svg+xml", ".svg")

    port = int(os.environ.get("PORT") or DEFAULT_PORT)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{port}/"
    print(f"Card Gallery server running: {url}")
    print(f"- Cards: {CARDS_PATH}")
    print(f"- Frame: {FRAME_PATH}")
    print(f"- Workflow: {WORKFLOW_PATH}")
    print("Set COMFYUI_URL to override ComfyUI endpoint.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")


if __name__ == "__main__":
    main()







