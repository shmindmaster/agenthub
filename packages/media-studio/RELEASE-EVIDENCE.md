# Release evidence contract

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
Compare all eleven Media Studio skill trees through every active host's declared
path (including registered surface aliases), and compare the four runtime gates
and capture/composition tools against source. Native plugins require a separate
native update and installed-content freshness check. Existing sessions must
reload instructions; installed file parity does not prove session compliance.

The sync tools (`build-cue-sheet.mjs`, `validate-sync.mjs`, `sync-lib.mjs`) are part of the same deployed set.

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

After every recut, write `qa/viewer-release-evidence.json` and run:

```powershell
node <media-studio>/scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>
```

Every review must carry the SHA-256 of that exact candidate. The gate requires:

- `captions`: a PASS SRT review; two readable lines per cue, 42 characters per line, 84 per cue, and no more than 20 characters per second.
- `audio`: PASS measurement at -16 LUFS ±1.5 and at or below -1 dBTP, linked by path and hash to the exact-candidate `ffmpeg-loudnorm` analyzer report.
- `pronunciation`: PASS, `reference: "authored-script"`, source script path/hash, and `releaseEligible: true`. ASR remains diagnostic and cannot be its own pronunciation reference.
- `encodedVisualReview`, `titleReview` (no duplicate opening title treatment), and `actionResultReview`. Each action event records action, visible-result, and spoken-result timestamps; the sentence cannot precede the picture.
- Product screencasts: `qa/encoded-picture.json` must be a passing `validate-encoded-picture.mjs` report for the exact candidate SHA-256 and byte count, with empty errors, ≥70% screen, source-bound screen segments, and canonical 6-second static / 12-bit dHash limits. A self-declared `encodedVisualReview` PASS cannot replace it.
- Product screencasts: `qa/sync.json` must be a passing `validate-sync.mjs` report for the exact candidate SHA-256 and byte count (VIDEO-SYNC-DIRECTIVE): screen up by the first content word, each narrated action within ±300 ms of its spoken verb or object, result held ≥1.5 s after it is shown and named, no result named before it appears, A/V drift ≤40 ms, no dropped frames, no exact-frame freeze over 4 s. It must use word-level narration timing (no `degraded`), canonical thresholds, list the checks it did not perform, and show at least one passed action-timing finding. It is built from `plan/cue-sheet.json` (`build-cue-sheet.mjs`); a passing report does not replace watching and listening to the file.
- `storyReview`: PASS and a concrete CTA. When the product demo is part of a series, it also records its stitchable `seriesId`/integer `chapter`.
- Profiled jobs: probe the exact encoded candidate for frame size and timeline duration. Campaign forms also enforce the form's 60–70, 60–80, 10–20, or 70–80 second range. These checks are in `validate-viewer-release.mjs`.
- Campaign forms: `job.campaign` binds dated claims to hashed evidence, every capture-manifest clip used in the composed picture to a hashed asset with origin/rights, and derivative jobs to a parent candidate and reused source hashes. Screen-video assets must declare `origin: captured-ui`; non-screen cutaways may use their actual origin. Unused takes need not be listed. Continuity is either one record and scenario or distinctly labeled vignettes. Portrait clips require explicit normalized `sourceRegion` framing in `capture/manifest.json`, preserved by the compose map and verified against the receipt-bound source by `validate-encoded-picture.mjs`. Portrait campaigns declare `captionRegion`; the exact-candidate `captions` PASS records `placementReviewed: true` and the same `region`. `story/timed-graphics.json` can time provenanced PNG overlays within frame safe areas and away from declared product controls and captions. If overlays exist, `timedGraphicReview` is a candidate-bound PASS confirming timing and control visibility; labeled vignettes also confirm visible labels. The contract checks that each vignette label covers the opening of its own segments and does not run over another vignette.

The gate is evidence-bound, not a replacement for human review. It catches a missing review, a stale review after a recut, and measurable defects; a reviewer still watches and listens to the encoded candidate.
