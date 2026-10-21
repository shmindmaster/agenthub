---
name: media-storyboard
description: Use when a media-studio screenplay needs a timed storyboard — shot plan, visual archetype, sound, rhythm, eye direction, and scored hook options — before directing or generating.
---

# Media storyboard

Turn the locked screenplay into a designed sequence of viewer experiences. You do not generate media, rewrite claims, or release.

Load `../media-studio/references/engagement.md`, `story-craft.md`, `cursor-flow.md`, and `scene-archetypes.md` unless kind is `product-screencast` (`product-picture.md` + `cursor-flow.md`). When `programForm` is `technical-story`, load `../media-studio/references/technical-story.md` and lay the beats on its timestamp map (hook → scenario → weird behavior → what is actually happening → code reveal → fix before/after → replay → what this means), whatever the kind. Marketing cuts also load `marketing-readiness.md`: the beats must put the hook on screen inside two seconds and cut on the bed.

Handoff: `media-writer` → **this skill** → `media-studio-visuals` → `media-director`.

## 1. Inputs

- `screenplay.json` matching `../../schemas/screenplay.schema.json`
- `qa/narration-check.json` with `ok: true` (the writer's no-fluff gate)
- `job.json` (`intent`, `kind`, `deliveryProfile`)

If the screenplay lacks `hook`, `sceneRole`, or `wiifm` on a viewer-facing job, or the narration check is missing or failing, remit to `media-writer`. Do not invent metrics or product behavior.

## 2. Hook choice (internal)

Write **2–3** hook/visual approaches. Score each 0–100 for: pain on screen inside five seconds (two for a marketing cut), picture that is not a title card, WIIFM, and truthfulness.

Keep the winner in `chosenHook`. Put the rest in `rejectedHooks` with `whyRejected`.

Prefer:

`chosenHook.narration: "One bad approval hides in a Monday-sized batch."` + `cold-open` B-roll of a dense queue

Avoid:

Showing the user a menu of three openings. Pick.

## 3. Beats

For every scene produce a beat with required storyboard fields: `sceneRole`, `visualArchetype`, `shotPlan`, `eyeDirection`, `expectedState`, `rhythm`, `sound`, `transition`. Set `visualMode`. On `product-screencast`, omit means `screen` (`product-picture.md`).

Rules:

1. Picture first, name the result after it appears. On `product-screencast`, each software beat is screen → control → action → visible response (`product-picture.md`). Set `startState` ≠ `expectedState` and `provesClaim`. Do not collapse a workflow into start → result.
2. **One eye path per beat.** Every screen beat and every guided static beat carries `eyePath: { start, move, rest }` (`cursor-flow.md`): where the eye already is, the one move toward the thing the line names, where it rests while the result is named. A beat that needs two moves is two beats. A beat whose line names nothing has no cursor motion. Loosening the pointer gate's defaults needs `pointer: { ..., reason }`; the default is zero reversals, zero scroll returns.
3. Exactly one `heroMoment: true`. Record `protectedHeroBeatId`.
4. Do not repeat `visualArchetype` on consecutive beats unless the continuation is intentional (`revealFrom` / checklist).
5. `rhythm.visualRefreshTarget` ≤ 4.5s for type-led beats; B-roll/motif may hold longer if the frame is still moving.
6. Hero / reveal: `sound.musicCue: silence` or `silenceOnReveal: true`.
7. `onScreen` ≤ 4 words. Do not duplicate narration. **Never a build chip, version chip, environment badge, revision label or "what's new" card.** Nothing redundant: a card that says what the voice says is cut.
8. Synthetic data is disclosed by a `syntheticDisclosure` caption or end-card beat (`mode: caption | end-card`), never by a spoken line.
9. Technical stories: every code, log, or cross-system beat names its markup in `shotPlan` (`box`, `dim`, `arrow`, `label`, `flow`) and exactly one highlight. A flow beat (`User → Web App → Tool Service → Integration → Zendesk`) precedes the code reveal when systems are crossed. The fix is one before/after beat. Plan a meaningful visual change every 5–15 s, each motivated by the story.
10. Marketing cuts: plan the cut grid on the bed's tempo (`cutsOnBeat.bpm`); the end card with the brand kit's CTA sits inside the last eight seconds; every beat is designed motion, not a held frame.

## 4. Output

Write `storyboard.json` matching `../../schemas/storyboard.schema.json`.

Then `media-studio-visuals`.

## 5. Final check

- [ ] Chosen hook scored; rejects recorded; no user menu; hook inside five seconds (two for marketing)
- [ ] One protected hero
- [ ] Every beat has shot plan, archetype, sound, rhythm; every screen or guided beat has one `eyePath`
- [ ] No accidental consecutive archetype repeat
- [ ] No build, version or revision chip; no card that repeats the voice; synthetic disclosure is a caption or end card
- [ ] Schema validates
