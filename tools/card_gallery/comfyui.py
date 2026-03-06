"""ComfyUI helper for generating inner card artwork.

No external dependencies: uses Python stdlib only.

This module is intentionally conservative:
- Loads a ComfyUI workflow JSON (API prompt graph).
- Injects prompt/negative/seed/size/filename_prefix.
- Submits job and polls until completion.
- Downloads the first produced image.

It supports two workflow JSON shapes:
- {"prompt": {<node_id>: {class_type, inputs, ...}, ...}, ...}
- {<node_id>: {class_type, inputs, ...}, ...}
"""

from __future__ import annotations

import copy
import json
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


class ComfyUiError(RuntimeError):
    pass


@dataclass(frozen=True)
class ComfyImageRef:
    filename: str
    subfolder: str
    type: str


def _http_json(method: str, url: str, payload: dict[str, Any] | None = None, timeout_s: float = 60.0) -> Any:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url=url, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read()
    except Exception as exc:  # noqa: BLE001
        raise ComfyUiError(f"HTTP {method} failed: {url}: {exc}") from exc

    try:
        return json.loads(body.decode("utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise ComfyUiError(f"Invalid JSON from {url}") from exc


def _http_bytes(url: str, timeout_s: float = 120.0) -> bytes:
    req = urllib.request.Request(url=url, method="GET", headers={"Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            return resp.read()
    except Exception as exc:  # noqa: BLE001
        raise ComfyUiError(f"Download failed: {url}: {exc}") from exc


def load_workflow(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _get_prompt_graph(workflow: dict[str, Any]) -> dict[str, Any]:
    if isinstance(workflow.get("prompt"), dict):
        return workflow["prompt"]

    # Some exports are already the prompt graph.
    if all(isinstance(v, dict) and "class_type" in v for v in workflow.values() if isinstance(v, dict)):
        return workflow

    raise ComfyUiError(
        "Workflow JSON format not recognized. Expected a ComfyUI API prompt graph (either top-level 'prompt' or graph dict)."
    )


def _find_nodes(prompt: dict[str, Any], class_type: str) -> list[tuple[str, dict[str, Any]]]:
    result: list[tuple[str, dict[str, Any]]] = []
    for node_id, node in prompt.items():
        if not isinstance(node, dict):
            continue
        if node.get("class_type") == class_type:
            result.append((str(node_id), node))
    return result


def _find_nodes_with_inputs(prompt: dict[str, Any], *, has_keys: set[str]) -> list[tuple[str, dict[str, Any]]]:
    result: list[tuple[str, dict[str, Any]]] = []
    for node_id, node in prompt.items():
        if not isinstance(node, dict):
            continue
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            continue
        if has_keys.issubset(set(inputs.keys())):
            result.append((str(node_id), node))
    return result


def inject_into_workflow(
    workflow: dict[str, Any],
    *,
    positive_prompt: str,
    negative_prompt: str | None,
    seed: int,
    width: int,
    height: int,
    filename_prefix: str,
) -> dict[str, Any]:
    """Return a modified copy of the workflow JSON with injected settings."""

    wf = copy.deepcopy(workflow)
    prompt = _get_prompt_graph(wf)

    # SaveImage
    save_nodes = _find_nodes(prompt, "SaveImage")
    if not save_nodes:
        raise ComfyUiError("Workflow missing a SaveImage node.")
    _save_id, save_node = save_nodes[0]
    save_inputs = save_node.setdefault("inputs", {})
    if not isinstance(save_inputs, dict):
        raise ComfyUiError("SaveImage.inputs is not a dict.")
    save_inputs["filename_prefix"] = filename_prefix

    # Seed: find any node with inputs.seed
    seed_nodes = _find_nodes_with_inputs(prompt, has_keys={"seed"})
    if not seed_nodes:
        raise ComfyUiError("Workflow missing a node with inputs.seed (e.g., KSampler).")
    _seed_id, seed_node = seed_nodes[0]
    seed_node["inputs"]["seed"] = int(seed)

    # Width/height: find any node with both.
    size_nodes = _find_nodes_with_inputs(prompt, has_keys={"width", "height"})
    if size_nodes:
        _size_id, size_node = size_nodes[0]
        size_node["inputs"]["width"] = int(width)
        size_node["inputs"]["height"] = int(height)

    # Prompts: CLIPTextEncode nodes
    text_nodes = _find_nodes(prompt, "CLIPTextEncode")
    if not text_nodes:
        raise ComfyUiError("Workflow missing CLIPTextEncode nodes for prompt text.")

    pos_marker = "__CARD_POS_PROMPT__"
    neg_marker = "__CARD_NEG_PROMPT__"

    pos_node = None
    neg_node = None

    for _nid, n in text_nodes:
        inputs = n.get("inputs")
        if not isinstance(inputs, dict):
            continue
        existing = inputs.get("text")
        if existing == pos_marker:
            pos_node = n
        elif existing == neg_marker:
            neg_node = n

    # Fallback: first = positive, second = negative
    if pos_node is None:
        pos_node = text_nodes[0][1]
    if neg_node is None and len(text_nodes) > 1:
        neg_node = text_nodes[1][1]

    if not isinstance(pos_node.get("inputs"), dict):
        raise ComfyUiError("Positive CLIPTextEncode.inputs is not a dict.")
    pos_node["inputs"]["text"] = positive_prompt

    if negative_prompt is not None and neg_node is not None:
        if not isinstance(neg_node.get("inputs"), dict):
            raise ComfyUiError("Negative CLIPTextEncode.inputs is not a dict.")
        neg_node["inputs"]["text"] = negative_prompt

    return wf


def submit_and_wait(
    comfyui_url: str,
    *,
    prompt_graph: dict[str, Any],
    timeout_s: float = 300.0,
    poll_interval_s: float = 0.5,
) -> str:
    comfyui_url = comfyui_url.rstrip("/")
    payload = {"prompt": prompt_graph, "client_id": "card_gallery"}
    result = _http_json("POST", f"{comfyui_url}/prompt", payload, timeout_s=60.0)

    prompt_id = result.get("prompt_id")
    if not prompt_id:
        raise ComfyUiError(f"ComfyUI /prompt did not return prompt_id. Response: {result}")

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        history = _http_json("GET", f"{comfyui_url}/history/{prompt_id}", None, timeout_s=60.0)
        # ComfyUI returns {prompt_id: {...}} when complete
        if isinstance(history, dict) and prompt_id in history:
            return prompt_id
        time.sleep(poll_interval_s)

    raise ComfyUiError(f"Timed out waiting for ComfyUI prompt_id={prompt_id}")


def get_first_image_ref(comfyui_url: str, prompt_id: str) -> ComfyImageRef:
    comfyui_url = comfyui_url.rstrip("/")
    history = _http_json("GET", f"{comfyui_url}/history/{prompt_id}")
    entry = history.get(prompt_id)
    if not isinstance(entry, dict):
        raise ComfyUiError("History entry not found after completion.")

    outputs = entry.get("outputs")
    if not isinstance(outputs, dict):
        raise ComfyUiError("History.outputs missing or invalid.")

    for _node_id, out in outputs.items():
        if not isinstance(out, dict):
            continue
        images = out.get("images")
        if not isinstance(images, list) or not images:
            continue
        first = images[0]
        if not isinstance(first, dict):
            continue
        filename = first.get("filename")
        subfolder = first.get("subfolder", "")
        img_type = first.get("type", "output")
        if filename:
            return ComfyImageRef(filename=str(filename), subfolder=str(subfolder), type=str(img_type))

    raise ComfyUiError("No images found in ComfyUI history outputs.")


def download_image_bytes(comfyui_url: str, ref: ComfyImageRef) -> bytes:
    comfyui_url = comfyui_url.rstrip("/")
    qs = urllib.parse.urlencode({"filename": ref.filename, "subfolder": ref.subfolder, "type": ref.type})
    return _http_bytes(f"{comfyui_url}/view?{qs}")
