# Screencast compositor and annotation layer

Shared tooling for screencast-led films (product screencasts, technical stories). Canonical source is this folder; the runtime copy is `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\screencast\` (synced by `packages/media-studio/scripts/Sync-MediaStudioKit.ps1`). Run `npm install` once in the runtime kit so `playwright` resolves. Every input and output lives in the external job workspace; nothing here reads or writes a product repository except `render-code.mjs`, which reads one source file read-only.

| Script | Produces |
| --- | --- |
| `compose-screencast.mjs <jobRoot> <base>` | `output/<base>-silent.mp4` — the silent picture, aligned to `story/narration-timeline.json`, from `capture/manifest.json` clips |
| `render-overlay.mjs <out.png> '<spec>'` | Transparent 1600×1000 annotation PNG: dim-with-cutout box, outline, labels, arrows, notes |
| `render-code.mjs <out.png> '<spec>'` | Code-reveal card: real source excerpt with line numbers and highlight bands, provenance in the footer |
| `render-html.mjs <out.png> <file.html>` | Typeset card or flow diagram from an HTML body |
| `render-card.mjs <out.png> '<spec>'` | Title / end / number card; auto-used for narration segments with no clip |

Frame is 1600×1000 30 fps (`briefing-board`); letterbox or scale to the delivery profile afterwards, then finish loudness with `Finish-Media.ps1`.

## Manifest hints (`capture/manifest.json` → `clips[]`)

| Hint | Type | Effect |
| --- | --- | --- |
| `segments` | `["S03","S04"]` | Timeline segment ids or scene ids the clip covers. Several clips naming one scene are dealt to its segments in order. |
| `trimStart` | seconds | Drop the head of the clip before anything else. |
| `trimEnd` | seconds | Stop reading the clip here. |
| `speed` | number > 1 | Retime the whole clip faster (real wait time such as a production query). |
| `skip` | `[[a,b],...]` | Seconds to drop from inside the clip (dead time, a mis-click). |
| `fit` | `cut` \| `hold` \| `fit` \| `fitpad` | `cut`: play from the start, stop at the narration end (default when the clip is longer). `hold`: play, then freeze the last frame (default when shorter). `fit`: retime the clip to the narration length. `fitpad`: like hold, explicit. |
| `overlay` | `overlays/S07.png` | Transparent PNG from `render-overlay.mjs`, composited over the scaled frame for this clip's segments. One overlay per clip; split a clip when the markup changes mid-beat. |

A segment with no clip holds the previous clip's last frame. A `.png` clip is a card, looped for the segment. Segments without any clip and no card get an auto card from the storyboard beat (`kicker`, `title`, `subtitle`, `footer`) or `job.json` (`title`, `cardFooter`).

## Overlay spec (`render-overlay.mjs`)

```json
{ "dim": 0.55,
  "boxes": [{ "x": 120, "y": 240, "w": 640, "h": 180, "label": "Webhook", "labelPos": "above" }],
  "arrows": [{ "from": [760, 330], "to": [1040, 330], "label": "DB write" }],
  "notes": [{ "x": 1060, "y": 420, "text": "Retry fires before the row commits" }] }
```

Coordinates are in the 1600×1000 delivery frame. Only the first box carries the dim; later boxes are outlines. Use `label` for the technical-story vocabulary (`User action`, `Webhook`, `DB write`, `Async job`) and an arrow for cause → effect.

## Sequencing rules (measured)

- Playwright-recast writes `.recast-tmp` inside the clips directory; concurrent renders into one directory fail with `EPERM`. Render sequentially per directory or use separate directories.
- Long many-click clips (about 117 s with ~40 clicks) can fail Recast's ffmpeg render; render without `autoZoom` or split the take and let `compose-screencast.mjs` join the pieces through `segments`.
