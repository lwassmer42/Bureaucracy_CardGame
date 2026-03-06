# Card Gallery Dev Tool (ComfyUI)

Local web gallery to design/approve cards (text + art) without touching Godot scenes.

## Run

From the repo root:

```powershell
python .\tools\card_gallery\server.py
```

Then open the printed URL (default `http://127.0.0.1:8787/`).

### Config

- `PORT`: override web server port
- `COMFYUI_URL`: override ComfyUI endpoint (default `http://127.0.0.1:8188`)

Example:

```powershell
$env:PORT = "8787"
$env:COMFYUI_URL = "http://127.0.0.1:8188"
python .\tools\card_gallery\server.py
```

## Files

- Frame layout: `design/frame_bureaucracy.json`
- Card data: `design/cards_bureaucracy.json`
- Backups: `design/backups/`
- ComfyUI workflow: `tools/comfyui/workflows/card_art_inner.json`
- Generated art output: `art/generated/card_art/<card_id>/<card_id>_seed<seed>.png`
- Imported art (UI **Import** button) is also saved under `art/generated/card_art/<card_id>/...` and auto-added as a variant.

## Workflow requirements (ComfyUI)

The generator expects your workflow JSON (API prompt graph) to include:
- at least one `CLIPTextEncode` node (positive prompt)
- optionally a second `CLIPTextEncode` node (negative prompt)
- a node with `inputs.seed` (e.g. `KSampler`)
- a node with `inputs.width` + `inputs.height` (e.g. `EmptyLatentImage`) (optional but recommended)
- a `SaveImage` node (we set `filename_prefix`)

### Recommended markers

To make node selection deterministic, set the `text` field in your workflow to these placeholders:
- positive prompt node: `__CARD_POS_PROMPT__`
- negative prompt node: `__CARD_NEG_PROMPT__`

If markers are missing, the tool uses the first `CLIPTextEncode` as positive and the second as negative.

## Notes

- The frame is currently referenced as an SVG: `art/bureaucracy_card_frame_blank_template.svg`.
  If you later export a PNG (e.g. `art/bureaucracy_card_frame_blank_600x900.png`), you can point `design/frame_bureaucracy.json` at it.
- Generated images are downloaded via the ComfyUI `/view` endpoint and saved into the repo.
