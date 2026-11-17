---
name: finish
description: Assembles accepted voice, picture and plates into a mastered video, then has a fresh reviewer score it and decide if it ships. Use when someone asks to assemble, render, cut, mix, fix loudness, deliver, review, score or QA a video. Not for making new assets; use produce.
---
# Finish
## Workflow contract
1. Use the accepted assets from `produce` and the locked storyboard.
2. Compose and render with the official Remotion plugin on the authorized remote render lane in a disposable workspace (the private compute guidance names the lane and its dates; never render on the operator's PC, and verify the pulled-back file's hash and size before cleaning up the worker); master loudness; write captions as a sidecar `.srt`. Delivery sizes follow the job profile (for example 1920×1080 or 1080×1920).
3. Have a fresh, separate reviewer score the encoded candidate and list defects and scenes to revise; return the deliverable and verdict.
4. If a gate fails, recut first, then recapture, then rewrite; never ship a failing candidate.
Read when assembling: [compose](references/compose.md), [render lanes](references/render-lanes.md), [loudness](references/loudness.md), [library](references/library.md), [compose detail](references/compose-detail.md).
Read when reviewing: [review](references/review.md), [gates](references/gates.md), [story review rubric](references/story-review-rubric.md), [review detail](references/review-detail.md).