---
name: media-studio-visuals
description: Use when a media-studio job needs art direction, a visual bible, B-roll, shot concepts, or truthful non-product-UI imagery, and must not fabricate product UI or metrics.
---

# Media studio visuals

Art direction for the job. You do not generate TTS, compose the program, or invent product UI.

Load `../media-studio/references/engagement.md` and `scene-archetypes.md`. Local images: `ai.ps1 image` / Visual Bank (`local-ai-stack` `references/image.md`). Exact logos and legal text are compositor type.

Screencast visual contract (kind `product-screencast`): `$Pds\pipeline\product-demo-studio\references\Visual-Asset-Guide.md`.

Handoff: `media-storyboard` → **this skill** → `media-director`.

## 1. Visual bible

Write `visual-bible.json` matching `../../schemas/visual-bible.schema.json`.

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
- [ ] Next skill is `media-director`
