# Card Prompting Guidelines

This file is the source of truth for bureaucracy card-art prompting. Use it whenever adding or regenerating cards in `design/cards_bureaucracy.json`.

## Global House Style

Positive:

`Ink art of [subject with attitude], [action/pose energy], [max 2 environment props], [lighting mood], [1 or 2 optional accent colors to focus on], graphic novel illustration, bold ink outlines, flat colors, limited color palette, high contrast, clean linework, strong silhouette, dramatic lighting, professional comic art`

Negative:

`photorealistic, 3d render, anime, manga, soft gradients, painterly, watercolor, airbrush, neon colors, bright saturated colors, glowing effects, fantasy lighting, blur, bokeh, soft focus, watermark, logo, speech bubbles, text, letters, numbers, extra limbs, deformed hands, extra fingers, bad anatomy, duplicate figures, multiple people unless specified`

## Prompt Strategy

Prompt for mood, pose energy, and atmosphere instead of literal card mechanics.

Formula:

`[subject with attitude] + [action/pose energy] + [max 2 environment props] + [lighting mood] + [1 or 2 optional accent colors]`

Examples:

- `stern supervisor, arm thrust forward in judgment, floating memo copies, harsh fluorescent glare, crimson accent`
- `exhausted worker, collapsed over a desk, one filing cabinet and a desk lamp, amber overtime lighting, muted teal accent`
- `sealed red folder, tilted like evidence, plain background, dramatic spotlight, red and brass accents`

## Construction Rules

For each card prompt:

1. Start with `Ink art of`.
2. Add one subject, described by role and attitude rather than a literal job title.
3. Add one action or pose with strong readable body language.
4. Add at most one or two environmental props.
5. Add a lighting or mood note.
6. Add one or two accent colors only if they help focus the image.

Keep each positive prompt under 120 tokens. Longer prompts weaken the style anchors.

## Avoid

- Literal card mechanics.
- Branded or overly specific objects.
- Complex multi-step actions.
- Multiple simultaneous concepts.
- Multiple people unless the card explicitly needs them.

## Batch Notes

- Randomize the seed per card.
- If `contains_people` is false, bias toward `object only, isolated on plain background` and avoid figure descriptors.
- Generate 4 variants per card by default.
- Preferred ComfyUI Lightning settings when the workflow exposes them: 8 steps, CFG 2.0, scheduler `sgm_uniform`.
