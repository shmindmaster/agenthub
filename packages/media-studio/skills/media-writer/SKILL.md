---
name: media-writer
description: Use when a video, briefing, training film, or explainer needs a screenplay, narration script, shot list, or scene-by-scene spoken words.
---

# Media writer

From the concept or outline already in context, produce a locked screenplay in this turn. Do not ask for act structure, tone, or shot count — infer them.

## Output

- `screenplay.json` matching `../../schemas/screenplay.schema.json`
- `narration.md` — canonical spoken text, one scene per heading, no phonetic respelling

## Rules

1. One idea per scene. Spoken sentences stay short (~150 wpm for duration).
2. Default truth `FACT` when the source is given; tag `DRAMATIZED` / `COMPOSITE` only when you heighten or merge.
3. Owner-voice scripts stay canonical. Pronunciation is a Local-AI dictionary layer at render time — never respell.
4. Do not invent metrics, customer names, or product behavior. Unsourced numbers are omitted, not guessed.
5. Product-UI claims that must be *shown* as a running app get `visualMode: screen` (captured later). Everything else defaults to `slide` for briefings/training and `diagram` for structure explainers.
6. Do not generate TTS. Hand the locked text to `media-studio-generate` immediately.
