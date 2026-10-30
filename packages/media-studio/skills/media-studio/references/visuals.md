# Visuals (art direction, visual bible, B-roll)

Step 3 of the crew in `SKILL.md`. Art direction for the job. You do not generate TTS, compose the program, or invent product UI.

Read with this step: `engagement.md` and `scene-archetypes.md`. Generated stills: accepted plates first, else Azure `gpt-image-2.5-flare` (`media-studio-generate` §4). Exact logos and legal text are compositor type.

Screencast visual contract (kind `product-screencast`): `Visual-Asset-Guide.md` plus `product-picture.md`. Product UI is captured video, not a bible still.

Order: `storyboard.md` → **this step** → `direction.md`.

## 1. Visual bible

Write `visual-bible.json` matching `../../../schemas/visual-bible.schema.json`.

Required: motif, lighting, typography, compositionRules, graphicalLanguage, motionTreatment, texture, continuity, brollPlan.

The bible makes this film look designed, not like the last briefing with new bullets.

Prefer:

`motif: dense queue collapsing to twelve exceptions` / `motionTreatment: slow push on before-state; snap cut on reveal`

Avoid:

`dark slides, yellow type` as the entire bible.

## 2. Shot concept per B-roll beat

For each `brollPlan` row: intent (problem/outcome/context/proof/texture), subject, prompt, refuse (product UI, metrics, testimonials).

Framing follows the storyboard `shotPlan` (close / wide / slow-push). Foreground/background must serve the focalPoint.

## 3. Continuity

One accent, one type ramp, one card language. Transitions match `transition.semanticReason` (chaos → controlled queue is a match-cut, not a random fade).

Never synthesize product UI, customer evidence, metrics, or testimonials.

## 4. Final check

- [ ] Bible validates
- [ ] Every B-roll beat has intent + refuse
- [ ] Motif is specific to this job
- [ ] Next step is `direction.md`
