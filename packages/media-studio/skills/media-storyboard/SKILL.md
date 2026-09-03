---
name: media-storyboard
description: Use when a media-studio screenplay needs a timed storyboard — shot plan, visual archetype, sound, rhythm, eye direction, and scored hook options — before directing or generating.
---

# Media storyboard

Turn the locked screenplay into a designed sequence of viewer experiences. You do not generate media, rewrite claims, or release.

Load `../media-studio/references/engagement.md`, `story-craft.md`, and `scene-archetypes.md` unless kind is `product-screencast` (PDS script-storyboard-generator).

Handoff: `media-writer` → **this skill** → `media-studio-visuals` → `media-director`.

## 1. Inputs

- `screenplay.json` matching `../../schemas/screenplay.schema.json`
- `job.json` (`intent`, `kind`, `deliveryProfile`)

If the screenplay lacks `hook`, `sceneRole`, or `wiifm` on a viewer-facing job, remit to `media-writer`. Do not invent metrics or product behavior.

## 2. Hook choice (internal)

Write **2–3** hook/visual approaches. Score each 0–100 for: pain-in-5s, picture that is not a title card, WIIFM, and truthfulness.

Keep the winner in `chosenHook`. Put the rest in `rejectedHooks` with `whyRejected`.

Prefer:

`chosenHook.narration: "One bad approval hides in a Monday-sized batch."` + `cold-open` B-roll of a dense queue

Avoid:

Showing the user a menu of three openings. Pick.

## 3. Beats

For every scene produce a beat with required storyboard fields: `sceneRole`, `visualArchetype`, `shotPlan`, `eyeDirection`, `expectedState`, `rhythm`, `sound`, `transition`.

Rules:

1. Picture first, name the result after it appears.
2. Exactly one `heroMoment: true`. Record `protectedHeroBeatId`.
3. Do not repeat `visualArchetype` on consecutive beats unless the continuation is intentional (`revealFrom` / checklist).
4. `rhythm.visualRefreshTarget` ≤ 4.5s for type-led beats; B-roll/motif may hold longer if the frame is still moving.
5. Hero / reveal: `sound.musicCue: silence` or `silenceOnReveal: true`.
6. `onScreen` ≤ 4 words. Do not duplicate narration.

## 4. Output

Write `storyboard.json` matching `../../schemas/storyboard.schema.json`.

Then `media-studio-visuals`.

## 5. Final check

- [ ] Chosen hook scored; rejects recorded; no user menu
- [ ] One protected hero
- [ ] Every beat has shot plan, archetype, sound, rhythm
- [ ] No accidental consecutive archetype repeat
- [ ] Schema validates
