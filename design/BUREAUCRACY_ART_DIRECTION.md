# Bureaucracy Deck — Art Direction (House Style + Subject Guidance)

This is the persistent “north star” for card art prompts so we don’t lose intent as we iterate.

## Tone
- Satirical / darkly humorous workplace bureaucracy.
- Humor comes from *human emotion* + *petty bureaucratic absurdity*.

## People (when present)
Prioritize expressive faces and clear body language:
- exhausted, stressed, forced smile, tight jaw, side-eye, clenched teeth
- head-in-hands, slumped shoulders, hunched posture over paperwork
- fake-positive “yes boss” energy while obviously miserable
- passive-aggressive office politeness, thinly veiled resentment

Good “comedy beats”:
- employee fake-smiling at their boss while hiding scissors behind their back
- clerk overwhelmed by forms that multiply off the desk
- someone stamping “APPROVED” on nonsense with dead eyes (no readable text)
- coworker quietly shredding documents while maintaining eye contact

## Scene Variety (not just the office)
Keep the bureaucracy vibe, but vary locations:
- crowded office, records room, hallway, break room
- city sidewalk, bus stop, post office, coffee shop, park bench
- government building lobby, DMV-like waiting area, security checkpoint

## Visual Constraints
- No readable text, no logos, no watermarks.
- Keep composition clean and graphic (readable silhouette + clear focal point).
- If a person is present, face should be visible enough to read emotion.

## Prompt Recipe (for `Subject / Scene`)
Write 1–2 sentences worth of comma-separated fragments:
1) **Who** (optional): “frazzled clerk”, “stern supervisor”, “overworked office worker”
2) **Emotion/gesture**: “forced smile”, “grimacing”, “head in hands”, “side-eye”
3) **Absurd bureaucratic prop/action**: forms, stamps, filing cabinets, shredders, red tape
4) **Location**: office / street / coffee shop / park etc.
5) **Lighting/composition**: “hard desk lamp shadows”, “clean graphic composition”, “medium shot”

Example structure:
- `overworked clerk, forced smile, hiding scissors behind back, standing beside stern supervisor, stacks of forms, office hallway, hard shadows`

## Example Subjects (copy/paste starters)
- `frazzled office worker, head in hands, paperwork avalanche sliding off desk, rubber stamp in the foreground, records room, hard desk lamp shadows`
- `nervous clerk, fake smile, hiding scissors behind back, stern boss with clipboard, stacks of forms, office hallway, medium shot`
- `tired bureaucrat on a park bench, briefcase spilling forms, forced smile at a passing supervisor, city park, late afternoon shadows`
- `coffee shop counter, exhausted worker clutching a stack of forms like a coffee order, barista unimpressed, street scene visible through window`
- `city sidewalk, filing cabinet on a hand truck, frustrated employee dragging it uphill, papers fluttering, dramatic simple composition`
- `waiting room full of blank-faced people holding identical forms, one person side-eyeing the camera, subtle absurdity, clean graphic composition`
## House Style (base prompt)
Use this as the fixed “house style” prefix. Keep *specific subjects/locations/actions* in the per-card `Subject / Scene` prompt.

**Positive base**
- `1970s comic book illustration, retro pulp print look, bold black ink outlines, clean confident linework, flat cel shading, subtle halftone / newsprint texture, limited warm palette (cream, tan, muted earth tones) with slightly richer midtones, clear value contrast and hard-edged shadows, simple graphic composition, no readable text`

**Negative base**
- `photorealistic, 3d render, soft gradients, painterly, watercolor, neon colors, modern digital art, anime, manga, bright saturated colors, glowing effects, fantasy lighting, blur, bokeh, soft focus, readable text, watermark, logo`


## People Ratio (60/40)
Aim for **~60% of cards with no people** in the artwork (object/scenery focused), and **~40% with people**.

Reason: SDXL Lightning tends to fumble hands/faces more often; we get better consistency by leaning on props, environments, and absurd object gags.

Pipeline note:
- Use `contains_people = false` on cards that should avoid humans (the generator adds extra “no people” negatives).
- Leave \\contains_people\\ unset / null (People In Art = Auto) to let the generator auto-balance toward the target mix; set it to true/false only when you want to force it.
