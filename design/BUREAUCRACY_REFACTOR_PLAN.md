# Bureaucracy Deckbuilder Refactor Plan

This file is the session handoff for future chats.

## Repo choice

Use `Deck_Builder_Tutorial/deck_builder_tutorial` as the production base.

Do not migrate gameplay into `roguelike_deckbuilder`.

Why:
- `deck_builder_tutorial` already has the real game loop: map, battles, rewards, shop, relics, save/load, statuses, enemy flow.
- It already has the bureaucracy card pipeline: `design/cards_bureaucracy.json`, card gallery, ComfyUI generation, promotion into Godot assets, promoted card loading.
- `roguelike_deckbuilder` is useful as a reference for desktop-scale project settings and cleaner presentation direction, but not as the implementation base.

## Core findings

### 1. The source art was not the problem
Promoted card art was already high resolution.

Example:
- `art/promoted/card_icons/bureaucracy_audit.png` is 1216x824.

The in-game degradation came from the project render/stretch setup, not from low-resolution source files.

### 2. The main fidelity problem was project-wide pixel rendering
The old project settings were effectively treating the whole game like a pixel-art game:
- `window/size/viewport_width=256`
- `window/size/viewport_height=144`
- `window/stretch/mode="viewport"`
- nearest/default pixel texture filtering

That caused high-fidelity bureaucracy art to be rendered into a tiny framebuffer and then blown up.

### 3. The right fix is to modernize the current repo, not backtrack into another template
The best path is:
- keep the current repo as the runtime/gameplay base
- adopt desktop-friendly display/render behavior
- refactor presentation scene by scene
- keep battle logic and progression logic intact while visuals evolve

## Changes already landed

### Display and fidelity foundation
`project.godot`
- `window/stretch/mode` changed from `viewport` to `canvas_items`
- `window/stretch/aspect="keep"` added
- `textures/canvas_textures/default_texture_filter=1`

Effect:
- high-resolution card art now survives the trip to screen much better
- old tutorial art may look soft or inconsistent during the transition, which is acceptable

### Full-card renderer groundwork
`scenes/ui/card_visuals_full.tscn`
`scenes/ui/card_visuals_full.gd`
- reusable full-card renderer based on `design/frame_bureaucracy.json`
- loads promoted art and bureaucracy metadata
- used by full-card preview / popup flows
- isolated from the legacy global pixel font theme

### Preview / tooltip groundwork
`scenes/dev/promoted_card_preview.tscn`
`scenes/dev/promoted_card_preview.gd`
`scenes/ui/card_tooltip_popup.gd`
- full-card preview exists for promoted cards
- tooltip popup uses the full-card renderer

### Runtime card metadata groundwork
`custom_resources/card.gd`
`custom_resources/card_pile.gd`
`global/promoted_cards.gd`
`scenes/event_rooms/helpful_boi_event.gd`
- added runtime instance fields like `instance_uid`, `upgrade_tier`, `reviewed_stacks`, `keywords`
- duplication paths now assign instance IDs

### Current browse behavior preference
Current desired behavior is:
- deck inspection / rewards / shop show compact small-card previews
- clicking a card opens the larger full-card view
- fidelity should remain high even in the compact preview, as much as current layouts allow

## Current status

What works now:
- promoted bureaucracy cards appear in rewards/shop/deck flow
- source art is rendering with much better fidelity than before
- compact browse previews remain the active interaction model for current scenes
- full-card popup / preview path exists

What is still legacy:
- battle hand is still the old tutorial compact card system
- many screens are still laid out around tiny 256x144-era assumptions
- the game is not yet authored as a true modern desktop 2D layout

## Recommended next steps

### Phase 1. Keep current repo and move to a real desktop logical space
Goal:
- stop treating `256x144` as the long-term authored space

Next work:
- raise the logical layout baseline toward a real PC space such as 1280x720
- reflow core scenes instead of just scaling them
- start with the least risky shared surfaces

Order:
1. `scenes/run/run.tscn`
2. `scenes/battle/battle.tscn`
3. top-bar / deck / tooltip overlays
4. reward/shop panels

### Phase 2. Preserve compact previews, improve compact art presentation
Goal:
- small cards still look like intentional previews, not crushed posters

Options:
- tune the compact preview widget to crop/frame the bureaucracy art better
- optionally create a dedicated bureaucracy compact-card preview scene that is not the old tutorial card shell
- keep click-to-expand full-card behavior

### Phase 3. Replace battle hand presentation
Goal:
- keep the gameplay logic, replace the hand presentation

Plan:
- introduce a new hand-card visual that is readable at desktop size
- likely use a medium-card presentation for hand cards instead of tiny tutorial cards
- keep targeting/dragging behavior intact while swapping visuals

### Phase 4. Expand data-driven promoted card runtime
Goal:
- promoted cards become genuinely playable content, not just visual entries

Plan:
- extend `cards_bureaucracy.json` with gameplay fields
- add effect data / simple DSL for common effects
- keep script escape hatches for unusual cards

### Phase 5. Bureaucracy-specific systems
Add after the presentation foundation is stable:
- Budget / deficit economy
- Backlog pile
- Archive / file behavior
- chain / approval mechanics
- photocopier / delayed copy behavior
- performance review / downgrade systems
- curse cards

## Implementation guidance

### Keep this rule
Do not rewrite the game into `roguelike_deckbuilder`.
Use it only as a reference for:
- desktop project settings
- cleaner baseline layout assumptions
- non-pixel presentation direction

### Treat legacy assets as disposable
It is acceptable if old tutorial art looks wrong during the transition.
The bureaucracy presentation direction matters more than preserving the tutorial art style.

### Prefer incremental playability
Each presentation refactor slice should leave the game runnable.

## Quick tests after future slices

### Fidelity check
- open deck view, reward, or shop
- compare a promoted bureaucracy card against its source artwork
- verify the source still looks materially similar in-game

### Compact preview check
- card previews remain small in deck/reward/shop
- clicking opens the larger full-card popup

### Regression check
- start a run
- complete a battle
- open rewards
- visit shop
- inspect deck
- confirm no crashes and promoted cards still appear

## Immediate next step for the next session

Do the first real desktop-layout refactor slice.

Recommended target:
- `scenes/battle/battle.tscn`
- `scenes/run/run.tscn`

Goal of that slice:
- keep current gameplay behavior
- re-author the UI positions for a desktop-scale layout
- do not change battle logic yet

## Workspace note

For future sessions, open the repo root directly at:
- `C:\Users\Lucas\Godot\Deck_Builder_Tutorial\deck_builder_tutorial`

That avoids working one folder too high and makes git/status/file navigation cleaner.
