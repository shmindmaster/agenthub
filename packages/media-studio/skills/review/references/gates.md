# Release gates

Cheapest first, in `scripts/`. `all` is every kind, `screen` is `product-screencast`, `marketing` is a marketing cut. Run `build-cue-sheet.mjs` after the last compose, before order 11.

| Order | Gate | Run when | Writes | Catches | On failure |
| --- | --- | --- | --- | --- | --- |
| 1 | `validate-storyboard.mjs` | Episode storyboard (`segments[]`) | Nothing | Broken story order, contract | Storyboard |
| 2 | `validate-narration.mjs` | all | `qa/narration-check.json` | Fluff, repeats, hook past 5 s | Writer |
| 3 | `write-story-review.py` | all | `qa/story-review.json` | Lint score below 85 | Named scenes |
| 4 | `Test-SpeechIntegrity.ps1` | Each voice take | Nothing | Dead air, low level, duration skew | Re-render take |
| 5 | `validate-demo-scenario.mjs` | screen | Nothing | Unproven workflow | Readiness handoff |
| 6 | `validate-capture-preflight.mjs` | screen, in `record-job.mjs` | `qa/capture-preflight.json` | Scene id, keyword, typing faults | Capture plan |
| 7 | `validate-capture-manifest.mjs` | After capture | Nothing | Bad manifest | Capture |
| 8 | `validate-product-picture.mjs` | screen, in compose | Nothing | Not live WebM, no Recast, hidden freeze | Recapture |
| 9 | `validate-pointer-path.mjs` | screen | `qa/pointer-path.json` | Reversal, travel over 1.35x, scroll return | Re-record beat |
| 10 | `validate-picture-inputs.mjs` | Before Remotion | Nothing | Wrong clock, changed number | Fix inputs |
| 11 | `validate-encoded-picture.mjs` | screen | `qa/encoded-picture.json` | Unbound clip, dead screen over 6 s | Recompose |
| 12 | `validate-frame-integrity.mjs` | all | `qa/frame-integrity.json` | Tiled frame, luma jump | Re-render |
| 13 | `validate-picture-integrity.mjs` | screen | `qa/picture-integrity.json` | Upscale, stretch, crop, bars | Recapture |
| 14 | `validate-word-sync.mjs` | `syncClock` or opt-in | `qa/word-sync.json` | Drift over 40 ms | Word clock |
| 15 | `validate-sync.mjs` | screen | `qa/sync.json` | Action off 300 ms, hold under 1.5 s | Recut beat |
| 16 | `validate-marketing-readiness.mjs` | marketing | `qa/marketing-readiness-check.json` | Below floor | Recut |
| 17 | `validate-viewer-release.mjs` | all, every recut | Nothing | See below | Owning gate |

Order 17 reads `qa/viewer-release-evidence.json`. It refuses a missing, stale or loosened report, and checks captions (2 lines, 42 per line, 84 per cue, 20 per second), audio (-16 LUFS ±1.5 or `loudnessTargetLufs`, at most -1 dBTP), `pronunciation` (`authored-script`, `releaseEligible`), title, action-result, `storyReview` CTA, frame size, duration and campaign forms.

It binds candidate reports to the exact SHA-256 and bytes, reviews to the SHA-256, the narration check to its script and pointer path to `capture/receipt.json`. A recut voids every candidate-bound report. An mvg job may file `media-studio/mvg-picture-gate` for order 11.

## Pronunciation

ASR cannot be its own reference. A proper noun or homophone it cannot confirm needs a verified lexicon entry or an owner listen. Otherwise report it unconfirmed and do not mark it release-eligible.

Decide pronunciation before synthesis, not after. `scripts/check_script_terms.py <locked-script.txt>` is free and offline: it exits 1 while any acronym, brand, name or stray capital has no `entries` (pinned IPA) or `plain` row in `scripts/pronunciation_lexicon.json`, and prints the `pin` list for `generate(..., pronunciations=[...])`. Pinning is the fix; the check below is the proof.

After synthesis run `scripts/check_name_pronunciation.py <jobRoot> --names A,B --negative-control [--anchors DIR]`. It scores each whole line with Azure Pronunciation Assessment at phoneme level and reads the name's own word result in context, then writes `qa/name-pronunciation.json`. Never score one-word clips cut from a sentence: their edges drop sounds and gave false failures on Penske and Forman. Verdicts: `FAIL`, `CHECK_NOT_DISCRIMINATING` (the negative control did not fail, so the check proves nothing), `AUTOMATED_PASS_UNCONFIRMED`, `CONFIRMED`. Only `CONFIRMED` is release-eligible, and it needs an anchor clip said correctly plus a lexicon entry set to `confirmed` by the name's owner or a verified recording. The report lists what it did not run: a model-based phone recognizer (remote compute only; local AI is off) and a human listen.
