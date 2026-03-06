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


## Promote to Godot

In the gallery, select a card and an art variant, then click **Promote**.

This writes tracked Godot assets:
- `art/promoted/card_icons/<card_id>.png`
- `common_cards/promoted/<card_id>.tres`

Promoted cards are automatically included in rewards and the shop when running the game (debug builds put promoted cards first so you can see them immediately).

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

## Recovering a lost prompt

If you generated an image in ComfyUI and lost the exact prompt, ComfyUI usually embeds it inside the PNG.

From the repo root:

```powershell
python .\tools\comfyui\extract_prompt_from_png.py path\to\your.png
```

It prints the `CLIPTextEncode` text nodes (typically positive + negative) and a small sampler/size summary.

## House style prompts

If `design/cards_bureaucracy.json` defines:
- `house_style_positive_default`
- `house_style_negative_default`
- `color_accent_suffix_default`

…then the generator will build prompts like:
- **Positive** = `house_style_positive_default` + optional `"<color_accent> accent color <suffix>"` + `card.art_prompt`
- **Negative** = `house_style_negative_default` + `card.negative_prompt` (or `negative_prompt_default`)

Per-card optional fields:
- `color_accent` (string)
- `use_house_style` (bool, default `true`)

## Art direction

See design/BUREAUCRACY_ART_DIRECTION.md for tone + subject/scene guidance (humorous bureaucracy, expressive faces, varied locations).

