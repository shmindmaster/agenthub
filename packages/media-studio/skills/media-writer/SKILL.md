---
name: media-writer
description: Use when a video, briefing, training film, or explainer needs a screenplay, narration script, shot list, or scene-by-scene spoken words.
---

# Media writer

From the concept or outline already in context, produce a locked screenplay in this turn. Do not ask for act structure, tone, or shot count — infer them.

Load `../media-studio/references/engagement.md`, `story-craft.md`, `studio-craft.md`, and `program-forms.md` unless kind is `product-screencast` (PDS script craft + outcome-first rules in `program-forms.md`).

Handoff: this skill → `media-storyboard`. Do not generate TTS.

## 1. Output

- `screenplay.json` matching `../../schemas/screenplay.schema.json` — `hook`, `emotionalTarget`, `viewerPromise`; per scene `sceneRole`, `viewerQuestion`, `wiifm`, `story`, `emphasis`, `pauseBeforeSeconds`, `holdAfterSeconds`, `musicCue`
- `narration.md` — canonical spoken text, one scene per heading, no phonetic respelling

## 2. Rules

1. One idea per scene. One promise per film (`program-forms.md`). Spoken sentences stay short (~150 wpm; slower for documentary / ai-trust).
2. First sentence is payoff or pain. Do not open with a greeting, logo recap, agenda, or nav tour.
3. Dramatic spine from `story-craft.md`. Exactly one `heroMoment: true`. Outcome-workflow / AI forms: pain → task → system acts → human reviews → result.
4. Default truth `FACT` when the source is given; tag `DRAMATIZED` / `COMPOSITE` only when you heighten or merge.
5. Owner-voice scripts stay canonical. Pronunciation is a Local-AI dictionary layer at render time — never respell.
6. Do not invent metrics, customer names, or product behavior. Unsourced numbers are omitted, not guessed.
7. Product-UI claims that must be *shown* as a running app get `visualMode: screen`. Do not default every other beat to `slide` — leave `visualArchetype` for the storyboard, or hint it when the story requires a number, split, or B-roll.
8. Do not narrate visible chrome. Name the result after it appears.

Prefer:

`sceneRole: before` / `wiifm: "I don't spend Monday hunting the bad row."`

Avoid:

`Welcome back.` / five consecutive scenes with no `sceneRole`.

## 3. Final check

- [ ] Hook in the first sentence
- [ ] Every viewer-facing scene has role, WIIFM, viewerQuestion
- [ ] One hero
- [ ] Schema validates
- [ ] Next skill is `media-storyboard`
