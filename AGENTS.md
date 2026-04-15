# Repo Workflow

- Use `codex/*` feature branches for ongoing work.
- Push the feature branch to the remote before asking for merge.
- Open a GitHub pull request for review instead of merging directly to `main`.
- Wait for code review feedback before merging the feature branch to `main` on the remote.
- Keep unrelated Godot `.import` churn and other local noise out of commits unless the user explicitly asks for it.

## General Approach

- Prefer incremental Godot changes over broad rewrites.
- Preserve gameplay behavior while refactoring presentation.
- After each meaningful slice, provide a short `Quick test` the user can run.
- Before opening a PR, do a local QA pass:
  - `python -m py_compile` for touched Python pipeline files
  - headless Godot project load
  - a short state-ownership sanity pass for deck/backlog/save mutations if card runtime code changed
- For gameplay-flow changes, prefer the QA autoplay harness documented in `QA_AUTOPLAY.md`.
- If a branch is risky or the local worktree is noisy, use a clean temporary worktree for validation rather than disturbing the main workspace.

## Skills To Use

- Use `godot-2d-best-practices` when changing viewport/stretch, scene layout, UI, autoloads, transforms, performance-sensitive 2D code, or modernizing the desktop presentation.
- Use `godot-game-from-scratch` when building a new Godot gameplay slice or system from a bare template rather than only refactoring an existing runtime.

## Card Gallery Workflow

Source of truth:
- `design/cards_bureaucracy.json`

Gallery server:
- `tools/card_gallery/server.py`
- URL: `http://127.0.0.1:8787/`

What the gallery is for:
- create/edit card definitions
- edit rules text and art prompts
- generate/import art variants
- approve/promote/unpromote/delete cards
- control the promoted gameplay test pool without hand-editing Godot assets

Important behavior:
- `Delete Card` removes the card from `design/cards_bureaucracy.json` and also removes promoted Godot assets if the card was promoted.
- `Unpromote` removes only the promoted Godot assets and keeps the card in the gallery.
- Promoted cards are the runtime test pool for rewards/shop when the game is configured to use promoted-only rewards.

Promotion outputs:
- `art/promoted/card_icons/<card_id>.png`
- `common_cards/promoted/<card_id>.tres`

If generated art is missing but the card is still promoted, the Godot icon may still exist even when a gallery variant file is gone.

## ComfyUI Automated Workflow

ComfyUI endpoint:
- `http://127.0.0.1:8188/`

Workflow file:
- `tools/comfyui/workflows/card_art_inner.json`

Generator path:
- the gallery calls `/api/generate`
- the server loads the workflow JSON
- it injects prompt, negative prompt, seed, width, height, and filename prefix
- it submits to ComfyUI, waits for completion, downloads the first image, and records the variant in `design/cards_bureaucracy.json`

Expected workflow nodes:
- a `SaveImage` node
- a node with `inputs.seed`
- ideally a node with `inputs.width` and `inputs.height`
- one `CLIPTextEncode` node for positive prompt and optionally a second for negative prompt

Prompt placeholders:
- positive: `__CARD_POS_PROMPT__`
- negative: `__CARD_NEG_PROMPT__`

House style strategy:
- defaults live in `design/cards_bureaucracy.json`
- detailed prompting guidance lives in `design/CARD_PROMPTING_GUIDELINES.md`
- art direction north star lives in `design/BUREAUCRACY_ART_DIRECTION.md`
- if `contains_people = false`, bias prompts toward `object only, isolated on plain background`

Current house style format:
- Positive pattern: `Ink art of [subject with attitude], [action/pose energy], [max 2 environment props], [lighting mood], [1 or 2 optional accent colors to focus on], graphic novel illustration, bold ink outlines, flat colors, limited color palette, high contrast, clean linework, strong silhouette, dramatic lighting, professional comic art`
- Negative pattern: `photorealistic, 3d render, anime, manga, soft gradients, painterly, watercolor, airbrush, neon colors, bright saturated colors, glowing effects, fantasy lighting, blur, bokeh, soft focus, watermark, logo, speech bubbles, text, letters, numbers, extra limbs, deformed hands, extra fingers, bad anatomy, duplicate figures, multiple people unless specified`

Batch defaults:
- 4 variants per card unless the user asks otherwise
- prefer 8 steps, CFG 2.0, scheduler `sgm_uniform` when the workflow supports it
- vary seeds per card

## Gameplay/Card Runtime Notes

- `card.id` is the card definition identity.
- `card.instance_uid` is the runtime identity for one physical copy in a run.
- Moving the same card between deck/draw/discard/backlog should preserve `instance_uid`.
- Creating a truly new extra copy should create a fresh `instance_uid`.
- Backlog is intended as a real separate zone, not just discard-by-another-name.
- Promoted-card runtime behavior should stay data-driven where practical; only add bespoke script paths when the mechanic truly needs it.
