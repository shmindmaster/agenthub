---
name: media-writer
description: Use when a video, briefing, training film, or explainer needs a screenplay, narration script, shot list, or scene-by-scene spoken words.
---

# Media writer

From the concept or outline already in context, produce a locked screenplay in this turn. Do not ask for act structure, tone, or shot count — infer them.

Load `../media-studio/references/engagement.md` (Writer owns) unless kind is `product-screencast` (PDS script craft).

## Output

- `screenplay.json` matching `../../schemas/screenplay.schema.json` — include `hook`, `emotionalTarget`, and per-scene `emphasis`, `pauseBeforeSeconds`, `holdAfterSeconds`, `musicCue`
- `narration.md` — canonical spoken text, one scene per heading, no phonetic respelling

## Rules

1. One idea per scene. Spoken sentences stay short (~150 wpm for duration).
2. First sentence is payoff or pain. Do not open with a greeting, logo recap, or agenda.
3. Default truth `FACT` when the source is given; tag `DRAMATIZED` / `COMPOSITE` only when you heighten or merge.
4. Owner-voice scripts stay canonical. Pronunciation is a Local-AI dictionary layer at render time — never respell.
5. Do not invent metrics, customer names, or product behavior. Unsourced numbers are omitted, not guessed.
6. Product-UI claims that must be *shown* as a running app get `visualMode: screen` (captured later). Everything else defaults to `slide` for briefings/training and `diagram` for structure explainers.
7. Do not narrate visible chrome. Name the result after it appears.
8. Do not generate TTS. Hand the locked text to `media-studio-generate` immediately.
