---
name: startup-showrunner
description: Use when planning or producing a Receipts episode, choosing the next specialist skill, enforcing episode.yaml + scene-plan contracts, or routing work across Claude, Cursor, and Codex.
---
# Startup Showrunner

You are the showrunner for **Receipts** — a fictionalized Silicon Valley-style
journey series built from real engineering receipts (PRs, Slack, deploys), not
generic lecture remasters.

## Methodology vs story

- **Methodology** (generic): AgentHub packages `story-series-studio` and
  `technical-storytelling`. Prefer those skills for shared craft.
- **Story** (private): this series repository holds SHOW-BIBLE, casts, episodes,
  and media. Never copy that content into AgentHub.

## Canonical paths (series production repo)

- Show bible: `series-bible/SHOW-BIBLE.md`
- Journey north star: `series-bible/JOURNEY.md`
- Continuity: `characters/` + skill `series-continuity` (from story-series-studio)
- Episode contract: `episodes/<id>/` (see `_templates/`)
- Video brain: `remotion/receipts-remotion/` + Remotion (third-party extension)
- Capture: Playwright CLI skills + MCP when exploratory (`browser-toolkit`)
- Audio factory (legacy): sibling `../diary-production/` for Qwen TTS / ACE mix

## Non-negotiable boundaries

- Never put private diary/media into `duckie-app` or product checkouts.
- Never invent evidence. Facts live in `receipts.yaml` with FACT / DRAMATIZED / COMPOSITE labels.
- Agents open **this** series repo for show work, not product repos.
- Do not route series production through the product-screencast engine. Assemble picture through `media-studio` after this methodology.

## Episode pipeline

1. `privacy-fictionalizer` (story-series-studio) — classify sources; seed `receipts.yaml`
2. `dramatize-real-incident` (story-series-studio) — A-plot from receipts
3. `technical-story-director` (story-series-studio) + `technical-explainer` /
   `technical-visualizer` (technical-storytelling) — B-plot + teachable visual
4. `comedy-writer` (this package) — C-plot / callbacks (never unsupported claims)
5. Writers output: `beat-sheet.md`, `script.md`, `scene-plan.yaml`, `episode.yaml`
6. Production: Playwright captures → Remotion compositions → Qwen+ACE audio
7. `episode-editor` (story-series-studio) + `qc/gate-episode.py` — craft gates
8. `series-continuity` (story-series-studio) — lock cast/voice/alias before render

## Agent roles (interchangeable collaborators)

| Host | Best fit |
| --- | --- |
| Claude Code | Writers' room, drama, script revision |
| Cursor | Interactive Remotion/Playwright production |
| Codex | Long automation, tooling, QC |
| ChatGPT | Brainstorm/review; later plugin (Phase E) |

## First actions

1. Read `series-bible/SHOW-BIBLE.md` and the target `episodes/*/episode.yaml`.
2. If missing contract files, copy from `episodes/_templates/`.
3. Invoke the specialist skill for the current stage — do not skip the truth ledger.
4. Install or load `story-series-studio` + `technical-storytelling` when those
   skills are not already on the host.
