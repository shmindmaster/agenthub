# Release evidence contract

Exact-file hosted forced alignment may upload mono 24 kHz PCM16 as WAV or
lossless FLAC. The gate probes the declared codec, rate, channels and FLAC
bit depth, then compares every decoded PCM sample with the encoded candidate.
Container compression does not change the provider's unknown timing uncertainty
or the existing offset and drift thresholds.

Use this external-workspace contract for every viewer-facing product screencast. It does not impose title or sequence rules on non-product media.

## Fleet deployment

Native Claude/Codex installation alone does not update Cursor, Grok, Hermes, or
the other loose-skill hosts. Deploy both skill content and executable tools:

```powershell
./scripts/Sync-Capabilities.ps1 -Apply -CapabilityId media-studio
./packages/media-studio/scripts/Sync-MediaStudioKit.ps1
```

`Sync-AgentHub.ps1` manages host configuration; it is not the skill deployment
step. Inspect a refused user-modified skill before explicitly adopting it.
Compare all declared Media Studio skill trees through every active host's declared
path (including registered surface aliases), and compare the four runtime gates
and capture/composition tools against source. Native plugins require a separate
native update and installed-content freshness check. Existing sessions must
reload instructions; installed file parity does not prove session compliance.

The sync tools (`build-cue-sheet.mjs`, `validate-word-sync.mjs`, `validate-sync.mjs`, `sync-lib.mjs`) are part of the same deployed set, as are the video-standard gates (`validate-narration.mjs`, `validate-capture-preflight.mjs`, `validate-pointer-path.mjs`, `validate-frame-integrity.mjs`, `validate-marketing-readiness.mjs`, `build-contact-sheet.mjs`).

Loose-skill hosts execute gates from
`%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`. The briefing kit also has
the gates under its `screencast` directory. Never treat a missing gate or a
successful host-configuration sync as a release check.

## Before capture

1. Create `evidence/source-scenario.json` from a current synthetic demo-readiness handoff. It must record the actual authenticated workflow checks and visible states the recording will prove. Do not use a planned route, a hard-coded identifier, or a static fixture as source proof.
2. Create `evidence/demo-scenario-proof.json` with `synthetic: true`, one `scenarioId`, persona, problem, `hero` (`segmentId`, `beforeState`, `action`, `visibleResult`), outcome (`statement`, `evidence`), and generic continuity entities (`type`, `id`). Its `source` must be a `DEMO-READY` `product-readiness-handoff`, with a relative path, SHA-256, verification time, authenticated workflow, and an observed, hash-bound runtime outcome. The source file must live in this external job workspace.
3. Put the same `scenarioId` and an explicit CTA on the storyboard. A beat may reference only the proven entity type/id pairs. Run:

```powershell
node <media-studio>/scripts/validate-demo-scenario.mjs <jobRoot>
```

This is a pre-capture gate. A failed picker, contract mismatch, missing approval criteria, or a dashboard state without a visible resolution belongs in the source readiness handoff; repair the product in its separately authorized engineering task before recording.

## Exact encoded candidate

Marketing 2.0.8 uses explicit isolated compose/QA/delivery stages and immutable candidate IDs. QA cannot compose.
Every top-level gate and delivery decision binds to the selected candidate SHA. External-candidate QA requires the
expected SHA, original compose metadata directory and a separate `--qa-dir`; source job evidence stays read-only.
Containment resolves junctions/symlinks, including nonexistent output tails. QA records the sidecar SRT hash;
delivery rejects a missing or changed sidecar even when the encoded candidate and its gate bindings still match.

Jobs declaring `syncClock: "forced-aligner"` or `syncClock: "asr-anchored"`, or explicitly opting in with
`clockPolicy.allowAsrAnchored: true`, require `qa/word-sync.json`, bound to the exact candidate SHA/bytes,
cue sheet, locked script and alignment evidence. The ASR selector requires that explicit opt-in; unsupported
selectors fail closed. The report names the actual method: ASR-anchored timing is never relabeled forced alignment.
`ai.ps1 align` supplies a take/script-bound forced word clock on its 80 ms grid. The opted-in identity-PCM route
instead re-verifies the retained ASR response and complete normalized candidate/source PCM identity. It preserves
the source grid and unknown acoustic accuracy; a zero measured cue offset does not establish exact acoustic onsets.
Whisper only checks transcript text. Missing or invalid alignment cannot fall back to Whisper onset times.
Before Remotion, `scripts/validate-picture-inputs.mjs` refuses a missing props file, a Whisper word clock, a narration whose numbers differ from `story/fact-lock.json`, a spotlight word that is not the spoken word, an mp3 or a wav without a PASS receipt, and a named person on a role voice without dramatization. `scripts/render-program.mjs` passes `--props=` as one argument and deletes a picture whose duration does not match the voice.
The canonical 40 ms offset/drift limits are unchanged; the raw grid limits measurement accuracy. This patch is not
the proposed 2.1 rendered-pixel/action-evidence audit, and its receipt-based picture checks retain their stated limits.

Local vision reuses only an enabled existing vision-capable Local-AI route, without starting services or downloading
weights. An unavailable or retired route blocks the vision gate. Paid OpenAI requires explicit provider selection
and normal budget accounting. No missing review, unavailable service or proposed capability counts as a pass.

After every recut, write `qa/viewer-release-evidence.json` and run:

```powershell
node <media-studio>/scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>
```

Every review must carry the SHA-256 of that exact candidate. The gate requires:

- `captions`: a PASS SRT review; two readable lines per cue, 42 characters per line, 84 per cue, and no more than 20 characters per second. A cue that is itself faster than 20 characters a second passes only when `qa/caption-rate-bound.json` lists that cue, its text matches the report, and the report hash is on the captions review. Listing a cue does not relax the line limits. Spoken words stay intact.
- `audio`: PASS measurement at -16 LUFS ±1.5 and at or below -1 dBTP, linked by path and hash to the exact-candidate `ffmpeg-loudnorm` analyzer report.
- `pronunciation`: PASS, `reference: "authored-script"`, source script path/hash, and `releaseEligible: true`. ASR remains diagnostic and cannot be its own pronunciation reference.
- `encodedVisualReview`, `titleReview` (no duplicate opening title treatment), and `actionResultReview`. Each action event records action, visible-result, and spoken-result timestamps; the sentence cannot precede the picture.
  An explainer or teaser that enacts no actions may instead use `actionResultReview.mode: "settled-state"`. Both `job.json` and `story/storyboard.json` must explicitly declare matching `kind: "explainer"` or matching `kind: "teaser"`, and `noEnactedActions: true` for the whole film. A mixed recorded-state/diagram teaser retains its teaser classification; it must not claim whole-film conceptual animation. The exact-candidate PASS requires an identified independent reviewer and `observedStates` covering every storyboard beat and matching narration segment. Each entry names `segmentId`, the observed `state`, concrete encoded-picture `evidence`, `resultVisibleAtSeconds`, and `spokenResultAtSeconds`; both times must fall within the measured encoded duration, with picture proof preceding the spoken claim. Prepared labels are not independent observation. Enacted-action events, invented action timestamps, blanket skips, and product-screencast opt-ins are rejected. All other picture, audio, timing, caption and story requirements still apply.
- Product screencasts: `qa/encoded-picture.json` must be a passing `validate-encoded-picture.mjs` report for the exact candidate SHA-256 and byte count, with empty errors, ≥70% screen, source-bound screen segments, and canonical 6-second static / 12-bit dHash limits. A self-declared `encodedVisualReview` PASS cannot replace it.
- Product screencasts: `qa/sync.json` must be a passing `validate-sync.mjs` report for the exact candidate SHA-256 and byte count (VIDEO-SYNC-DIRECTIVE): screen up by the first content word, each narrated action within ±300 ms of its spoken verb or object, result held ≥1.5 s after it is shown and named, no result named before it appears, A/V drift ≤40 ms, no dropped frames, no exact-frame freeze over 4 s. It must use word-level narration timing (no `degraded`), canonical thresholds, list the checks it did not perform, and show at least one passed action-timing finding. It is built from `plan/cue-sheet.json` (`build-cue-sheet.mjs`); a passing report does not replace watching and listening to the file.
- Every kind: `qa/narration-check.json` must be a passing `validate-narration.mjs` report bound to the locked script it read (`story/screenplay.json`, or `story/narration-timeline.json` when no screenplay exists): no greeting, meta, recap, process, version or synthetic-data line, nothing said twice, every line adds something, hook and promise inside five seconds, synthetic disclosure as a caption or end card. The report carries fluff per minute and the words-cut report; a stale report (source hash changed) fails.
- Every kind: `qa/frame-integrity.json` must be a passing `validate-frame-integrity.mjs` report for the exact candidate SHA-256 and byte count: no tiled frame (a half-frame repeated), no luma jump off the edit list.
- Product screencasts: `qa/picture-integrity.json` must be a passing `validate-picture-integrity.mjs` report for the exact candidate: per product clip, uniform scale at or below 1.0 against the capture's native pixels, no crop that removes UI edges unless the cue plan declares it, no pillarbox or letterbox bars inside the product frame, Recast punch-in only where the cue plan declares it and the take was captured at device scale factor 2 or higher; and a 4:5 or 9:16 deliverable captured at its own viewport (receipt `viewport`, `ratio`, `device`) unless `job.json` declares `responsive: false` with a `responsiveException`.
- Product screencasts: `qa/pointer-path.json` must be a passing `validate-pointer-path.mjs` report bound to `capture/receipt.json`: per beat, zero direction reversals, zero scroll reversals or scroll returns, travel ≤ 1.35× the direct path through the named targets, zero moves not followed by a named action, unless the cue plan carries a `pointer` allowance with a reason. A receipt whose hash changed since the report fails.
- Marketing cuts (`programForm` campaign-*, `marketing-cutdown`, `social-clip`, `hero`; `kind: teaser`; `marketing: true`): `qa/marketing-readiness-check.json` must be a passing `validate-marketing-readiness.mjs` report for the exact candidate: hook on screen inside two seconds, one promise, designed motion and type, music bed and sound design, brand end card with one CTA inside the last eight seconds, ≥90% of cuts on the bed's grid, three cited reference ads, and the reviewer's feed verdict (`skills/media-studio/references/marketing-readiness.md`). Below the floor nothing else counts.
- `storyReview`: PASS and a concrete CTA. When the product demo is part of a series, it also records its stitchable `seriesId`/integer `chapter`.
- Profiled jobs: probe the exact encoded candidate for frame size and timeline duration. Campaign forms also enforce the form's 60–70, 60–80, 10–20, or 70–80 second range. These checks are in `validate-viewer-release.mjs`.
- Campaign forms: `job.campaign` binds dated claims to hashed evidence, every capture-manifest clip used in the composed picture to a hashed asset with origin/rights, and derivative jobs to a parent candidate and reused source hashes. Screen-video assets must declare `origin: captured-ui`; non-screen cutaways may use their actual origin. Unused takes need not be listed. Continuity is either one record and scenario or distinctly labeled vignettes. Portrait clips require explicit normalized `sourceRegion` framing in `capture/manifest.json`, preserved by the compose map and verified against the receipt-bound source by `validate-encoded-picture.mjs`. Portrait campaigns declare `captionRegion`; the exact-candidate `captions` PASS records `placementReviewed: true` and the same `region`. `story/timed-graphics.json` can time provenanced PNG overlays within frame safe areas and away from declared product controls and captions. If overlays exist, `timedGraphicReview` is a candidate-bound PASS confirming timing and control visibility; labeled vignettes also confirm visible labels. The contract checks that each vignette label covers the opening of its own segments and does not run over another vignette.

The gate is evidence-bound, not a replacement for human review. It catches a missing review, a stale review after a recut, and measurable defects; a reviewer still watches and listens to the encoded candidate.
