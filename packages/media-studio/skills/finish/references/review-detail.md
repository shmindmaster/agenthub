# Workflow detail


## Workflow

```text
- [ ] Gates: run references/gates.md cheapest first; any fail stops here
- [ ] Word clock: align the encoded file (references/word-clocks.md)
- [ ] Frames: sample cue boundaries and scene midpoints
- [ ] Judge: score against references/story-review-rubric.md
- [ ] Encoded pass: walk every scene against Diagnose first
- [ ] Release: validate-viewer-release.mjs after every recut
```

**Word clock.** ASR alignment clocks the picture only where `job.json` sets `clockPolicy.allowAsrAnchored: true`. Without that, a new film has no accepted word clock: report word-sync as blocked, never as passed.

**Frames.** `build-contact-sheet.mjs <jobRoot> <candidate.mp4>` writes `qa/contact-sheet.png`. `Inspect-MediaVisualQuality.ps1` and every metric are flags, not verdicts. For `product-screencast`, use the mute test in `../../video/references/product-picture.md`, not the inspector.

**Judge.** Use the rubric's vision-judge method and inputs; a `product-screencast` also needs a passing `validate-product-picture.mjs`. A missing or mutable input is `status: MALFORMED_INPUT`, never a pass.

Fail under `craftScoreMin` (default 85), on any `block` finding, or on any rubric Fail at any score condition, such as a missing hook or an unducked bed. Marketing cuts also need `qa/marketing-readiness-check.json` PASS on this candidate.

**Encoded pass.** Walk the Diagnose first table in `../../video/references/story.md`. Slow, repetitive, static or flat stretches go back to their owner. A story score cannot rescue a failed gate, and the screenplay lint authorizes nothing after capture.

**Pronunciation.** ASR cannot be its own reference: a name it cannot confirm is not release-eligible until confirmed per `references/gates.md`.
