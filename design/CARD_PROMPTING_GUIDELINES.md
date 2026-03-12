# Card Prompting Guidelines

This file is the source of truth for bureaucracy card-art prompting. Use it whenever adding or regenerating cards in `design/cards_bureaucracy.json`.

## Global House Style

Positive:

`Ink art of [subject], [action/pose if person or energy if object], [lighting mood], [accent color], graphic novel illustration, bold ink outlines, flat colors, limited color palette, high contrast, clean linework, strong silhouette, dramatic lighting, professional comic art`

Negative:

`photorealistic, 3d render, anime, manga, soft gradients, painterly, watercolor, airbrush, neon colors, bright saturated colors, glowing effects, fantasy lighting, blur, bokeh, soft focus, watermark, logo, speech bubbles, text, letters, numbers, extra limbs, deformed hands, extra fingers, bad anatomy, duplicate figures, multiple people unless specified`

## Prompt Strategy

Prompt for mood, pose energy, and atmosphere instead of literal card mechanics.

Formula:

`[subject] + [action/pose if person or energy if object] + [lighting mood] + [accent color]`

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
- Keep the deck-level mix near 60/40: about 60% no-people prompts and 40% people prompts with clear emotional expression.
- If `contains_people` is false, bias toward `object only, isolated on plain background` and avoid figure descriptors.
- If `contains_people` is true, explicitly include emotional tone in the subject/pose language.
- Generate 4 variants per card by default.
- Preferred ComfyUI Lightning settings when the workflow exposes them: 8 steps, CFG 2.0, scheduler `sgm_uniform`.
