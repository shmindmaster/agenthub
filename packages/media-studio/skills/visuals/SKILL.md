---
name: visuals
description: Chooses and builds each beat's picture: charts, hand-drawn diagrams, Lottie, generated stills, captured screens, NotebookLM drafts. Use when a scene needs something to look at, a draft is words in boxes, or diagrams or animation are asked for. Not narration; use generate.
---

# Visuals

Show the thing the line is about. A beat that shows a title, or the sentence again, has no picture.

## Choose from the ladder

Open `references/ladder.md`. It maps what the line says to the visual kind, the source, and the cost. Free lanes first: the Remotion kit, hand-drawn SVG, Lottie, Playwright capture. Paid lanes only when a free one cannot show it, and only the ones `scripts/route_media.py` returns as usable.

```text
py -3 scripts/route_media.py image --identity mahumtech
py -3 scripts/route_media.py diagram motion
```

## Build

- **Kit visuals, including chart, svg and lottie:** `references/kit-visuals.md`.
- **Design rules, anti-slop list, sizes for video:** `references/visual-bible.md`.
- **Lottie:** `references/lottie.md`.
- **NotebookLM as a research and draft lane:** `references/notebooklm.md`.
- **Exploring or diffing a page with a browser:** `references/browser-tools.md`.

## Check

Before any render, `check_picture_relevance.py` and `check_visual_variety.py`. After a render, build the contact sheet and look at it; a gate passing is variety and relevance, never taste.

## Rules that do not bend

- One claim per picture. Every arrow gets a verb. Every number gets a picture.
- The picture changes with every sentence.
- No text inside a generated image; text belongs in the kit so it can be read and checked.
- Never Ken Burns, auto cards, or animated screenshots standing in for a captured screen.
- A generated or drafted asset is shown to the owner with its price before it goes into a film.
