---
name: media-director
description: Use when a video needs direction, a visual plan, scene design, pointer and highlight choreography, talking-head blocking, or performance notes for local voice.
---

# Media director

Translate the locked screenplay into what appears and how it is performed. Decide in this turn; do not present a menu of visual styles. You do not capture, generate, or release.

Load `../media-studio/references/engagement.md` (Director owns) unless kind is `product-screencast` (PDS + Recast).

Defaults: briefing → motion slides (dark field, one headline, color-coded emphasis, **build in**, hold to speech). Explainer → diagram build or slides. Training → one idea per card. Talking-head → face plate + voice. Only use `screen` when a running product is the claim.

## Visual mode (per scene)

Prefer the cheapest truthful visual **that still changes when the idea changes**:

| Mode | When |
| --- | --- |
| `slide` | Briefing / training argument on type |
| `screen` | Claim is about a live product — `media-studio-capture` (Playwright + Recast). Do not load retired `product-demo*` skills. |
| `diagram` | Structure or flow (Mermaid/D2/SVG, not diffusion) |
| `talking-head` | Face must carry the line |
| `motif` | Generated motion from an enrolled still (problem/outcome B-roll, not product UI) |
| `animation` | Motion itself teaches; Remotion |
| `narration-only` | A visual would decorate |

A slide or diagram that does not build across the line is a still. Call a build, a cut, Motif, or B-roll rather than holding it for a second idea.

## Pointer, click, highlight

For `screen` scenes, specify:

- target locator / region
- pointer lead → action → visible feedback → result hold
- highlight vs zoom (one emphasis, not both unless the hold is the hero)

Recast (`playwright-recast`) owns cursor approach, click ripple, and punch-in zoom for captured product traces. Do not invent a second overlay stack.

For `slide` scenes, emphasis is type color, Remotion build-in, and hold time, not a fake cursor.

## Performance

Owner voice: name the style-bank register (`explaining`, `firm`, `serious`, …) from Local-AI's Sarosh bank. Do not write free-text "sound excited" instructions for that speaker. Role voices may use `--instruction`.

Set `musicCue` per scene (`bed` default for viewer-facing non-screencast; `silence` on the hero hold).

## Output

`direction.json` keyed by scene id: visualMode, on-screen copy, highlight, action, register, duration, musicCue, pauseBeforeSeconds, holdAfterSeconds. Then `media-studio-generate`.
