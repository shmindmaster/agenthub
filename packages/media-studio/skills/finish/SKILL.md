---
name: finish
description: Use when a film needs assembly, rendering, mixing, mastering, encoded review or delivery.
---
# Finish
## Workflow contract
1. Use the accepted assets from `produce` and the locked storyboard.
2. Use the requested composition route. For Remotion use the official plugin. Render on the authorized remote lane in a disposable workspace (the private compute guidance names the lane and its dates; never render on the operator's PC, and verify the pulled-back file's hash and size before cleaning up the worker); master loudness; write captions as a sidecar `.srt`. Delivery sizes follow the job profile (for example 1920×1080 or 1080×1920).
3. Have a fresh, separate reviewer score the encoded candidate and list defects and scenes to revise; return the deliverable and verdict.
4. Repair verified defects at their source and recheck the encoded candidate. Complete authorized internal delivery after QA. External publication requires separate approval for the actual candidate and destination.
## Check the experience in the delivered editions

Review the export against the brief, storyboard and spoken lines. Check whether the picture, slides and sound deliver the requested experience. Verify consequential factual claims against their sources, and check a verified product action in context. For illustrative scenes, judge correctness, readability, synchronization and the requested experience. Flag extended low-motion intervals for inspection; resolve idle passages with the actual action, a timed point of focus or a tighter edit. Keep useful reading time. A motion score alone cannot distinguish a useful explanation from a camera pan.

Review each complete sentence affected by a name repair in the final video and any listen-first mix. Check speaker continuity, word endings, pauses and caption alignment at the join. Report whether review used direct listening or automated analysis. For interview preparation, verify the short rehearsal route, chapter jumps and closing questions. For a reused product film, check the standalone and embedded clocks separately and carry the final seek points into the viewing guide.

For operator tutorials, have a reviewer unfamiliar with the route follow the encoded candidate from each role home using the documented synthetic starting state. Record timestamps, steps attempted, observed outcomes, handoffs and failures; repair omissions and repeat affected steps. Listen to the final encoded audio and watch it in the intended player with the sidecar captions enabled: check that spoken labels match visible controls when named, actions and results are in sync, and captions do not cover the controls or results. Report the player, direct listening, follow-along outcome and any unverified step; automated checks alone cannot establish this result.

For recapture jobs, match the encoded film and caption pair to the accepted build and the reviewed take list. Replace the released MP4 and sidecar SRT together after reviewing both, then read back both files. If the release changes an action, label, permission or outcome after capture, reopen the affected acceptance check before publishing.

Run `scripts/validate-finished-film.mjs` on every encoded candidate (open, gaps, silence, ending, aspect) and walk the human checklist in [gates](references/gates.md) for what it cannot read. When `story/requirements.json` exists, then run `check_requirements.py <jobRoot> --candidate out/<file>`; a requirement with no `match` term needs a timecoded item in `qa/requirements-review.json`.

Read when assembling: [compose](references/compose.md), [render lanes](references/render-lanes.md), [loudness](references/loudness.md), [library](references/library.md), [compose detail](references/compose-detail.md).
Read when reviewing: [review](references/review.md), [gates](references/gates.md), [story review rubric](references/story-review-rubric.md), [review detail](references/review-detail.md).