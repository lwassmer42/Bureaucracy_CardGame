"""Extract ComfyUI prompt info embedded in a PNG.

ComfyUI commonly embeds two PNG text chunks:
- key: "prompt"   (JSON prompt graph that includes CLIP text, sampler settings, etc.)
- key: "workflow" (the UI workflow graph)

This script prints the CLIPTextEncode text nodes (usually positive + negative),
plus a small summary of sampler + resolution nodes when present.

No external dependencies (stdlib only).
"""

from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path
from typing import Any


def _iter_png_chunks(fp):
    sig = fp.read(8)
    if sig != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Not a PNG file (bad signature)")
    while True:
        header = fp.read(8)
        if len(header) < 8:
            break
        length, ctype = struct.unpack(">I4s", header)
        data = fp.read(length)
        fp.read(4)  # CRC
        yield ctype, data
        if ctype == b"IEND":
            break


def _parse_png_text(ctype: bytes, data: bytes) -> tuple[str | None, str | None]:
    if ctype == b"tEXt":
        k, v = data.split(b"\x00", 1)
        return k.decode("latin1"), v.decode("latin1")
    if ctype == b"zTXt":
        k, rest = data.split(b"\x00", 1)
        if rest[:1] != b"\x00":
            return k.decode("latin1"), None
        return k.decode("latin1"), zlib.decompress(rest[1:]).decode("latin1")
    if ctype == b"iTXt":
        # keyword\0comp_flag\0comp_method\0lang\0translated\0text
        parts = data.split(b"\x00", 5)
        if len(parts) != 6:
            return None, None
        k, comp_flag, comp_method, _lang, _translated, text = parts
        if comp_flag[:1] == b"\x01":
            if comp_method[:1] != b"\x00":
                return k.decode("latin1"), None
            text = zlib.decompress(text)
        return k.decode("latin1"), text.decode("utf-8", errors="replace")
    return None, None


def _load_comfy_prompt_json(path: Path) -> dict[str, Any]:
    with path.open("rb") as fp:
        meta: dict[str, str] = {}
        for ctype, chunk in _iter_png_chunks(fp):
            if ctype not in (b"tEXt", b"zTXt", b"iTXt"):
                continue
            k, v = _parse_png_text(ctype, chunk)
            if k and v is not None:
                meta[k] = v

    raw = meta.get("prompt")
    if not raw:
        raise ValueError("No embedded ComfyUI 'prompt' chunk found in this PNG.")

    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("Embedded 'prompt' JSON is not an object/dict.")
    return parsed


def _extract_clip_texts(prompt_graph: dict[str, Any]) -> list[tuple[str, str]]:
    texts: list[tuple[str, str]] = []
    for node_id, node in prompt_graph.items():
        if not isinstance(node, dict):
            continue
        if node.get("class_type") != "CLIPTextEncode":
            continue
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            continue
        text = inputs.get("text")
        if isinstance(text, str):
            texts.append((str(node_id), text))
    return texts


def _extract_sampler_summaries(prompt_graph: dict[str, Any]) -> list[str]:
    summaries: list[str] = []
    for node_id, node in prompt_graph.items():
        if not isinstance(node, dict):
            continue
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            continue
        if "steps" in inputs and "cfg" in inputs and "sampler_name" in inputs:
            seed = inputs.get("noise_seed") if "noise_seed" in inputs else inputs.get("seed")
            summaries.append(
                f"node {node_id}: steps={inputs.get('steps')} cfg={inputs.get('cfg')} "
                f"sampler={inputs.get('sampler_name')} scheduler={inputs.get('scheduler')} seed={seed}"
            )
    return summaries


def _extract_size_summaries(prompt_graph: dict[str, Any]) -> list[str]:
    summaries: list[str] = []
    for node_id, node in prompt_graph.items():
        if not isinstance(node, dict):
            continue
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            continue
        if "width" in inputs and "height" in inputs:
            summaries.append(f"node {node_id}: {inputs.get('width')}x{inputs.get('height')}")
    return summaries


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("png", type=str, help="Path to a ComfyUI PNG (with embedded prompt/workflow)")
    ap.add_argument("--json", action="store_true", help="Output a JSON summary instead of text")
    args = ap.parse_args(argv)

    path = Path(args.png)
    prompt_graph = _load_comfy_prompt_json(path)

    clip_texts = _extract_clip_texts(prompt_graph)
    sampler = _extract_sampler_summaries(prompt_graph)
    size = _extract_size_summaries(prompt_graph)

    if args.json:
        out = {
            "file": str(path),
            "clip_texts": [{"node_id": nid, "text": t} for nid, t in clip_texts],
            "sampler_nodes": sampler,
            "size_nodes": size,
        }
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0

    print(str(path))

    if clip_texts:
        print("\nCLIPTextEncode texts:")
        for i, (nid, text) in enumerate(clip_texts):
            label = "positive" if i == 0 else "negative" if i == 1 else f"text_{i+1}"
            print(f"\n--- node {nid} ({label})")
            print(text.strip())
    else:
        print("\nNo CLIPTextEncode nodes found in embedded prompt graph.")

    if sampler:
        print("\nSampler-like nodes:")
        for s in sampler[:6]:
            print(f"- {s}")

    if size:
        print("\nSize nodes:")
        for s in size[:6]:
            print(f"- {s}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
