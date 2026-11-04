---
name: review
description: Decides whether an encoded candidate ships, with a score, defects and the scenes to revise. Use when someone asks to review, score, QA or verify a cut, check sync or ask if a film is ready. Not for fixing it; use compose or capture.
---

# Review

Judge the exact encoded file, not the proxy, the screenplay or the render log. Gate on defects, not on whether it rendered. Never say sync or visual quality is verified from a PASS report alone: inspect the rendered file and its audio, and name every check not performed. You do not edit media.

Four rules outrank every gate:

1. No fluff: every line earns its seconds; nothing spoken about synthetic data, versions, revisions or how the film was made.
2. Feed test for customer-facing cuts: it wins against references in the first five seconds.
3. Nothing redundant: one idea said once, no build or version chips.
4. Purposeful cursor: only to the next thing named, one direction per beat.

## Workflow

```text
- [ ] Gates: run references/gates.md cheapest first; any fail stops here
- [ ] Word clock: align the encoded file (references/word-clocks.md)
- [ ] Frames: sample cue boundaries and scene midpoints
- [ ] Judge: score against references/story-review-rubric.md
- [ ] Encoded pass: walk every scene against Diagnose first
- [ ] Release: validate-viewer-release.mjs after every recut
```

**Word clock.** `node <kit>/cloud/cloud-ai.mjs align --take <candidate> --script <script.txt> --out qa/encoded-alignment.json`, then `validate-word-sync.mjs` and `validate-sync.mjs` after `build-cue-sheet.mjs`. It clocks the picture only where `job.json` sets `clockPolicy.allowAsrAnchored: true`. Without that, a new film has no accepted word clock: report word-sync as blocked, never as passed.

**Frames.** `build-contact-sheet.mjs <jobRoot> <candidate.mp4>` writes `qa/contact-sheet.png`. Check word-clock drift with hosted ASR timestamps. `Inspect-MediaVisualQuality.ps1` and every metric are flags, not verdicts. For `product-screencast`, use the mute test in `../video/references/product-picture.md`, not the inspector.

**Judge.** The story-experience review reads the picture. Cite a timestamp or frame for every finding and ignore generator self-assessment. Use the rubric's vision-judge method. Required inputs: encoded candidate, contact sheet, screenplay, storyboard, visual bible, captions, `job.json`, `qa/narration-check.json`, and `qa/pointer-path.json` with screen beats. A `product-screencast` also needs a passing `validate-product-picture.mjs`. A missing or mutable input is `status: MALFORMED_INPUT`, never a pass.

Fail when the score is under `craftScoreMin` (default 85), on any `block` finding, or when the hook is missing, the hero count is not exactly one, the opening is a feature tour, the bed is unducked, the narration reads the slide, anything is said twice, or the cursor moves with nothing named. Marketing cuts also need `qa/marketing-readiness-check.json` PASS on this candidate.

**Encoded pass.** Walk the Diagnose first table in `../video/references/story.md`. Slow, repetitive, static or flat stretches go back to their owner. A story score cannot rescue a failed gate. A screenplay lint from `write-story-review.py` authorizes nothing after capture.

**Pronunciation.** ASR cannot be its own reference. A proper noun or homophone it cannot confirm needs a verified lexicon entry or an owner listen. Otherwise report it unconfirmed and do not mark it release-eligible.

## Output and loop

Write `qa/story-experience-review.json` per `schemas/story-experience-review.schema.json`: `score`, findings with location, evidence, fix and `owner`, and `reviseSceneIds`. `pass` is true only when `status` is `COMPLETE`, the score meets `craftScoreMin`, and no finding blocks.

On a fail, the owner reruns those scenes only, re-encodes, and this review runs again. Do not restart writer, capture or TTS. Continue to delivery only when it passes. A recut voids every candidate-bound report.

Input and output example: a cut with a slow middle gives `score: 78, pass: false, reviseSceneIds: ["s4","s7"], findings[0].owner: "media-storyboard"`, not "Looks pretty good."

## References

| File | Read when |
| --- | --- |
| `references/gates.md` | Running or auditing the release gates |
| `references/word-clocks.md` | Choosing or defending a word clock |
| `references/story-review-rubric.md` | Scoring a film |
| `references/marketing-readiness.md` | Reviewing a marketing cut |
