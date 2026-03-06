# Bureaucracy Deck – Card Pipeline Status (2026-03-06)

This file is a handoff summary so a fresh chat/thread can pick up quickly.

## What’s working now

### 1) Web Card Gallery (dev tool, not in-game)
- Local server: `tools/card_gallery/server.py`
- UI: `tools/card_gallery/web/`
- Lets you browse cards, pick art variants, edit text, save JSON, and generate more art via ComfyUI.

### 2) Card design source-of-truth
- `design/cards_bureaucracy.json`
  - Card fields: `id`, `name`, `cost`, `type`, `rarity`, `target`, `rules_text`, `art_prompt` (subject/scene)
  - Variants: `variants[]` with `seed` + `file`
  - Generation now stores metadata per variant: `prompt_id`, `positive_prompt`, `negative_prompt`, `width`, `height`, `generated_at`

### 3) Consistent “house style” prompt wrapper
- House defaults live in `design/cards_bureaucracy.json`.
- `tools/comfyui/workflows/prompt-builder.jsx` mirrors these values for reference.
- House style was updated to be *style-only* (no specific subjects/locations).

### 4) ComfyUI integration
- Workflow: `tools/comfyui/workflows/card_art_inner.json`
- Generator injects prompt/negative/seed/size and downloads the result via ComfyUI HTTP API.

### 5) Recover prompts from PNGs
- `tools/comfyui/extract_prompt_from_png.py` extracts embedded ComfyUI `prompt` text chunks (positive/negative + sampler + size).

### 6) Promote a card to Godot assets (for quick in-engine testing)
- Gallery button: **Promote**
- Server endpoint: `POST /api/promote { card_id }`
- Writes tracked Godot assets:
  - `art/promoted/card_icons/<card_id>.png`
  - `common_cards/promoted/<card_id>.tres`
- Game loads promoted cards dynamically from `res://common_cards/promoted/`:
  - Loader: `global/promoted_cards.gd`
  - Hooked into rewards and shop:
    - `scenes/battle_reward/battle_reward.gd`
    - `scenes/shop/shop.gd`
  - Debug builds prioritize promoted cards so you see them immediately.

### 7) Full-frame preview scene (600×900) in Godot
- `scenes/dev/promoted_card_preview.tscn`
  - Renders the frame SVG + inner art + text using the same layout as the web gallery.

## Known limitations
- In actual gameplay UI, cards still render as tiny “icon cards” (tutorial UI). Promoted art is high-res but gets crushed into a small icon.
- The bureaucracy 600×900 frame is not yet used in the main hand/reward/shop card UI.

## Next steps (recommended)
1) **Full-card visuals in-game**
   - Add a new `CardVisualsFull` scene (600×900) that matches the frame config.
   - Use it at least in card rewards + tooltip first (lowest risk), then optionally for hand cards.
   - Consider exporting the frame SVG to a PNG for more consistent rendering/perf.

2) **Icon generation for gameplay UI**
   - Either (A) keep small icons and generate a square thumbnail per card (center-crop), or
   - (B) switch gameplay UI to use the full framed card visuals.

3) **Effects / playability**
   - Add a “promote-to-playable” step that creates a `.gd` card script per promoted card and wires `apply_effects()`.
   - Define a minimal effect DSL in JSON for common effects (damage/block/status/draw) and generate scripts.

4) **Prompt improvements**
   - Add emotion/comedy constraints into the house prompt (style-only) or as optional per-card “tone” presets.
   - Add a “Copy positive/negative prompt” button per variant in the gallery.

## Quick test recipes
- Web gallery: `python tools/card_gallery/server.py`
- Godot full-frame preview: run `scenes/dev/promoted_card_preview.tscn` (F6) and set `card_id`.
- Gameplay quick check (debug): run the game and visit a shop/reward; promoted cards should appear first.
