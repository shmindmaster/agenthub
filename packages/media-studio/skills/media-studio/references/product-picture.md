# Product picture

Single home for “the product is the picture.” Skills point here; they do not restate this table.

Applies when `job.kind` is `product-screencast`, when `programForm` defaults to that kind (`program-forms.md`), or when a beat is `visualMode: screen`. A running product as the subject wins over “briefing”, “tutorial”, “walkthrough”, or “explainer.” If nothing on screen can act, the job is a `briefing` — do not label frozen screens a screencast.

Validator: `packages/media-studio/scripts/validate-product-picture.mjs <jobRoot>`. Compose and QA run it. Fail closed.

## Beat grammar

One action per beat:

`start → locator → pointer lead → action → visible product response → result hold`

Recast owns cursor approach, click ripple, punch-in zoom. Timing numbers live in the PDS killer-demo guide (eased pointer 400–600 ms, settle ≥250 ms, click pulse 300–400 ms, hold ≥500 ms, one snap-to-region 300–500 ms per beat, no `zoom.drift`). Do not copy those numbers here.

The compositor overlay (`render-overlay.mjs`) owns dim / box / arrow / label / flow. They stack; neither replaces the other. Native hover/focus/loading/toast is the proof the action worked — do not cover it with a fake cursor or a title card.

A `hold` is the last frame of the preceding WebM, or a storyboard-declared result hold on that video. It is not a PNG still and not `interaction.kind: none` posing as the picture.

## Allowed picture

| Beat | Picture | Forbidden |
| --- | --- | --- |
| Workflow, config, result | Playwright WebM + Recast | PNG still, Ken Burns / scale-pan on UI, Motif/I2V of a screenshot |
| Code | Product first, then overlay or a 5–20 line `render-code.mjs` card, then product result | A 40s+ Remotion code slide as the main picture |
| Flow / diagram | Overlay on the product, or ≤8s cutaway, then back | A chapter of slides between two screenshots |
| Title / CTA / Q card | Remotion card, ≤8s each | Auto-card filling a missing screen clip; a 40s card on a screencast |
| Diagnostic PNG | Poster, contact sheet, capture-plan note | The encoded picture of a `screen` beat |

Missing `visualMode` on a `product-screencast` beat **defaults to `screen`**, not `slide`.

## Ratio

≥70% of timeline duration is `visualMode: screen` with a `.webm` / `.mp4` clip. The rest may be cards, overlays, and code reveals. Below 70%, compose fails.

## Capture plan

`story/capture-plan.json` matches `schemas/capture-plan.schema.json`. Every `interaction` row names `locator`, `action`, `expectedResult`, and a video `clip` (source WebM). Keep the Playwright `trace` as metadata; do not encode trace JPEGs. `plateName: *.png` is not a capture for an interaction or hold row. `hold` is not a substitute for interaction on a workflow beat.

## Gates that must not pass a stills-and-slides cut

- `compose-screencast.mjs` does not auto-card a `screen` beat. No clip → throw.
- A `.png` clip on a `screen` beat → throw.
- Ken Burns on `screen-in-context` is off in the Remotion kit. Recast punch-in is the only zoom on product UI.
- `Inspect-MediaVisualQuality.ps1` flags `ken-burns-on-still` (tiny grayscale hash frozen while full-frame hashes change).
- `media-story-experience-reviewer` refuses `kind: product-screencast` (`MALFORMED_INPUT`). PDS story review runs on the **encoded** file only. A pre-capture text score is not a craft pass.
- Motif / image-to-video of a product screenshot is refused (`local-ai-stack` `references/video.md`).
- Card / `slide` / `diagram` beats on a `product-screencast` are each ≤8s.
- Recast (`playwright-recast@0.19.2`) is required pointer finishing (`product-video-policy.json` `pointerFinishing`). If Windows ffmpeg `autoZoom` fails on a long many-click clip, split the take or render without `autoZoom`. That is not permission to encode PNGs.
