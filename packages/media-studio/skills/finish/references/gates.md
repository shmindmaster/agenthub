# Release gates

Cheapest first, in `scripts/`. `all` is every kind, `screen` is `product-screencast`, `marketing` is a marketing cut. Run `build-cue-sheet.mjs` after the last compose, before order 11.

| Order | Gate | Run when | Writes | Catches | On failure |
| --- | --- | --- | --- | --- | --- |
| 1 | `validate-storyboard.mjs` | Episode storyboard (`segments[]`) | Nothing | Broken story order, contract | Storyboard |
| 2 | `validate-narration.mjs` | all | `qa/narration-check.json` | Fluff, repeats, hook past 5 s | Writer |
| 3 | `write-story-review.py` | all | `qa/story-review.json` | Lint score below 85 | Named scenes |
| 4 | `Test-SpeechIntegrity.ps1` | Each voice take | Nothing | Dead air, low level, duration skew | Re-render take |
| 5 | `validate-demo-scenario.mjs` | screen, in the recorder's pre-flight | Nothing | Unproven workflow | Rerun `write-scenario-proof.mjs` |
| 6 | `validate-capture-preflight.mjs` | screen, in `record-job.mjs` | `qa/capture-preflight.json` | Scene id, keyword, typing faults | Capture plan |
| 7 | `validate-capture-manifest.mjs` | Only a job with per-shot capture metadata (`captures`). Not applicable to the clips manifest of a `screen` job, which order 8 checks | Nothing | Bad per-shot metadata | Capture |
| 8b | `validate-screen-stage.mjs` | screen-stage films | `qa/screen-stage.json` | 60 fps, plan from receipt, spring curve, colour in motion, ghosting, fade in, result in view, unchanged holds, press response, capture rate (`screen-stage.md`) |
| 8 | `validate-product-picture.mjs` | screen, in compose | `qa/product-picture.json` | Not live WebM, no Recast, hidden freeze, edited or unknown receipt, wrong persona, scenario or build, a manifest file that is not there | Recapture |
| 9 | `validate-pointer-path.mjs` | screen | `qa/pointer-path.json` | Reversal, travel over 1.35x, scroll return | Re-record beat |
| 10 | `validate-picture-inputs.mjs` | Before Remotion | Nothing | Wrong clock, changed number | Fix inputs |
| 11 | `validate-encoded-picture.mjs` | screen | `qa/encoded-picture.json` | Unbound clip, dead screen over 6 s | Recompose |
| 12 | `validate-frame-integrity.mjs` | all | `qa/frame-integrity.json` | Tiled frame, luma jump | Re-render |
| 13 | `validate-picture-integrity.mjs` | screen | `qa/picture-integrity.json` | Upscale, stretch, crop, bars | Recapture |
| 14 | `validate-word-sync.mjs` | `syncClock` or opt-in | `qa/word-sync.json` | Drift over 40 ms | Word clock |
| 15 | `validate-sync.mjs` | screen | `qa/sync.json` | Action off 300 ms, hold under 1.5 s | Recut beat |
| 16 | `validate-marketing-readiness.mjs` | marketing | `qa/marketing-readiness-check.json` | Below floor | Recut |
| 17 | `validate-viewer-release.mjs` | all, every recut | Nothing | See below | Owning gate |
| 18 | `validate-finished-film.mjs` | all, on the encoded file, before order 17 is written. The mvg driver requires `finishedFilm` automatically when `finalHoldSeconds` is declared; otherwise opt in through `qa.required` | `qa/finished-film.json` | Black or blank open or gap, silence of 5 s or more, silent tail, unmet final hold, wrong aspect | Recut |

Order 17 reads `qa/viewer-release-evidence.json`. It refuses a missing, stale or loosened report, and checks captions (2 lines, 42 per line, 84 per cue, 20 per second), audio (-16 LUFS ±1.5 or `loudnessTargetLufs`, at most -1 dBTP), `pronunciation` (`authored-script`, `releaseEligible`), title, action-result, `storyReview` and the single opening title treatment and CTA for legacy verified and marketing cuts, frame size, duration and campaign forms.

It binds candidate reports to the exact SHA-256 and bytes, reviews to the SHA-256, the narration check to its script and pointer path to `capture/receipt.json`. A recut voids every candidate-bound report. For explicitly illustrative educational, explanation, fiction or abstract work without enacted product actions or completed product claims, set `noEnactedActions` and `noCompletedResultClaims` to true. If the job does not require an action-result review, record the candidate-specific representation assessment in `storyReview.representation`. Verify any current-product claim against source evidence. An mvg job may file `media-studio/mvg-picture-gate` for order 11.

## Finished film

`scripts/validate-finished-film.mjs <candidate> [--requirements story/requirements.json] [--deliverable narrated-video|silent-video|audio] [--reviewed-silence a-b[:reason]]...` measures only the encoded file with ffmpeg, so it is quick on a long film. Errors: black or single-colour first frame of 0.2 s or more; a near-uniform span over 0.5 s anywhere (a closing fade of 1 s or less is allowed); audio silence of 5 s or more mid-film unless listed as reviewed (one range per `--reviewed-silence` flag, or `reviewedSilences: [{start,end,reason}]` in requirements, reason required); trailing silence over 6 s when no `finalHoldSeconds` is declared, or over `finalHoldSeconds` + 3 s when one is; a declared `finalHoldSeconds` that the final picture does not meet (it must stay stable, not fade, not be black); a narrated film with no audio; an aspect (`16x9`; `16:9` is tolerated) or a `durationSeconds` `{min,max}` the film falls outside (any other shape is a `duration-invalid` error), or a `--deliverable` that contradicts `job.json`. The deliverable defaults from `job.json` (`deliverable`, or kind `audio-only` for audio), else narrated video; `stills` and `storyboard` return `ok` with `notApplicable` and measure nothing. The report carries `deliverable` and `requirementsSha256`. Advisories need a look and never block: still picture through the first 3 s, a final picture that is still under 2 s with no hold declared, silence of 3 to 5 s, trailing silence of 3 to 6 s with no hold declared (a held outcome card is wanted, so the advisory says whether the final picture was stable), a near-empty frame between busier ones (a possible loading or empty page: one whose edge detail is under 5% of pixels between frames above 8%), and a blurred-fill band on a vertical film. Each advisory names the timecode to open.

Calibration: blurred fill fired on the one real vertical cut tried (21 of 45 seconds) and on none of the landscape films. The low-detail advisory found a full-page spinner in a screen-recording film but not the spinner in a film with an in-app spinner, and a spinner inside an app shell with its own page content is not detected: it stays on the human checklist below. Tuning it further added false positives, so it was left there.

It does not read text, so these stay a human review of the contact sheet and the encoded file:

- No half line of text at any frame edge, in a product screen or a terminal.
- The smallest UI text the viewer must read is at least 22 px at 1080p (2% of frame height).
- No spinner, skeleton or blank page is left in the cut.
- The UI language matches the declared `uiLanguage` in every localized shot. Product text the app has not translated is Product-Readiness Feedback and is not re-labelled in the film.
- The last 5 s is a designed outcome state that names what changed, not a cropped page.
- A caption never covers the text being discussed.
- A 9:16 cut is recomposed from source captures at native framing, never a blurred fill or a side crop of a 16:9 master.

## Picture

`scripts/check_picture_relevance.py <props-or-picture-plan.json> <cue-sheet-or-screenplay.json>` (a picture plan and a screenplay work before any voice exists) exits 1 when a scene and a spoken line do not pair by id. It reports a scene with no visual body or fewer than two content words or numbers in common with its line as an editorial advisory; `--enforce-overlap` makes that a failure when the brief requires it. Titles and kickers do not count. It is the only mechanical check that the picture is about the words; frame integrity and word sync pass on a perfectly clean but irrelevant picture. It does not judge design, so also write the contact sheet (`build-contact-sheet.mjs`) and look at the frames before a picture is called good, filed or shared. Anything shown to the owner has been looked at first.

## Words only

`scripts/check_visual_variety.py <briefing-props.json>` checks picture share, consecutive scenes without pictures, overuse of one visual kind and repeated footage or stills without a `reuseReason`. Treat these counts as editorial signals; add `--enforce-style` when the brief requires the briefing picture mix. Compare intentional callbacks to their earlier use during the encoded review. Run this check with `check_picture_relevance.py` before any voice or render spend.

## Pronunciation

ASR cannot be its own reference. A proper noun or homophone it cannot confirm needs a verified lexicon entry or an owner listen. Otherwise report it unconfirmed and do not mark it release-eligible.

Decide pronunciation before synthesis, not after. `scripts/check_script_terms.py <locked-script.txt>` is free and offline: it exits 1 while any acronym, brand, name or stray capital has no `entries` (pinned IPA) or `plain` row in `scripts/pronunciation_lexicon.json`, and prints the `pin` list for `generate(..., pronunciations=[...])`. Pinning is the fix; the check below is the proof.

After synthesis run `scripts/check_name_pronunciation.py <jobRoot> --names A,B --negative-control [--anchors DIR]`. It scores each whole line with Azure Pronunciation Assessment at phoneme level and reads the name's own word result in context, then writes `qa/name-pronunciation.json`. Never score one-word clips cut from a sentence: their edges drop sounds and gave false failures on Penske and Forman. Verdicts: `FAIL`, `CHECK_NOT_DISCRIMINATING` (the negative control did not fail, so the check proves nothing), `AUTOMATED_PASS_UNCONFIRMED`, `CONFIRMED`. Only `CONFIRMED` is release-eligible, and it needs an anchor clip said correctly plus a lexicon entry set to `confirmed` by the name's owner or a verified recording. The report lists what it did not run: a model-based phone recognizer (remote compute only; local AI is off) and a human listen.
