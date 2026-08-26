---
name: product-demo-studio-render
description: Use when a demo-ready product screencast needs an episode plan, storyboard, Recast/FFmpeg render, or evidence package. For briefings, slides, talking-heads, or Remotion compositions, use media-studio-compose.
---

# Product Demo Render

Render from immutable capture, narration, storyboard, truth-sheet, and claim inputs in the external workspace. Do not create `apps/videos`, studio folders, or render dependencies in a product repository.

## Default stack

- Playwright CLI or Playwright Test captures a high-resolution WebM plus trace.
- Recast consumes the capture for pacing, cursor, click feedback, animated punch-in zoom, captions, and voice timing.
- `page.setContent()` supplies designed title and end cards without a compositor.
- FFmpeg performs the smallest required caption burn-in and delivery normalization.
- Remotion is reserved for concepts that genuinely require a custom composition.

Run `../../scripts/scaffold-video-workspace.mjs --repo <product-repo> --product <name>` once per external workspace. Keep all paths relative inside that workspace for Windows compatibility. Never overwrite a candidate; every render receives a new ID and checksum.

Render a proxy first. Check pacing, pointer/focus visibility, framing, zoom restraint, result holds, narration alignment, captions, title/end cards, and truthful claims. After approval, render the final candidate and generate the delivery spec, media metadata, contact sheets, scene boundaries, frame integrity, audio quality, motion analysis, claim verification, truth verification, and craft report expected by preflight. The craft report must checksum-bind a `render-timing` artifact and the exact final video. Rendered beat starts, actions, results, hero holds, and ends must match the canonical storyboard within one frame; meaningful actions must produce a measured before/result pixel change. The end card declares `stableFromSeconds`, remains fully stable for at least three seconds, and is checked on every decoded frame so brief localized motion cannot hide between samples.

The renderer creates candidates; it never approves release. Package only the exact candidate bytes accepted by Product Demo QA.
