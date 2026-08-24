---
name: product-demo-studio-qa
description: Use when a proxy or final product-video render needs evidence, truth, persuasion, accuracy, privacy, audio, caption, synchronization, accessibility, frame, playback, or reproducibility validation.
---

# Product Demo QA

QA is a fail-closed release system. Generator self-review is useful but never independent approval.

## Gate

1. Run deterministic technical checks and `../../scripts/preflight.mjs`. Findings conform to `../../schemas/video-finding.schema.json`; preflight binds reports and media to immutable hashes. Craft validation must include checksum-bound `render-timing` plus the exact final video, with rendered story timing within one frame and a fully stable final hold of at least three seconds.
2. After preflight passes, the orchestrator performs a block-only editorial audit of the exact media hash: watch the complete candidate start to finish and inspect the actual cold open, every transition/focus change, hero before/action/result, trust boundary, CTA, end-card entry, and stable final frame. Reject accidental toasts/widgets/tooltips, clipped or half-entered overlays, weak product framing, unreadable responsive variants, filler, a title/thumbnail promise the opening does not fulfill, or a result that lacks visible impact. Write the candidate-bound record defined by `../../schemas/editorial-audit.schema.json`; its continuous playback interval must cover the probed media duration and every phase must cite either a checksum-bound artifact or a timestamp/frame hash that the release validator can reproduce from the exact candidate. This audit can require remediation; it cannot replace the four independent reviews or the final verifier. Missing, failed, stale, or wrong-candidate audit evidence blocks arbitration.
3. Dispatch four fresh read-only reviewers with execution receipts:
   - `../../agents/story-experience-reviewer.agent.md`
   - `../../agents/screen-accuracy-compliance-reviewer.agent.md`
   - `../../agents/audio-captions-sync-reviewer.agent.md`
   - `../../agents/technical-frame-integrity-reviewer.agent.md`
4. Validate every report with `../../scripts/validate-review-report.mjs`. Missing, malformed, writable, or non-independent review evidence blocks release. The orchestrator or isolated audio reviewer must also listen to the exact encoded candidate continuously and produce `../../schemas/candidate-listening-receipt.schema.json`; the receipt must bind the candidate path, hash, bytes, source revision, render provenance, ffprobe duration, and listening interval. A failed receipt blocks `PASS` and routes its findings to `REMEDIATE`; missing, shortened, stale, or wrong-candidate listening evidence blocks arbitration without requesting recurring owner approval.
5. Dispatch `../../agents/release-arbiter.agent.md` in a fresh read-only context. Validate its decision with `../../scripts/validate-release-decision.mjs`.
6. For REMEDIATE, issue the least-privilege assignment, fix only validated findings, render a new candidate, and rerun preflight, the orchestrator editorial audit, and affected reviews. Product and pipeline blockers return explicit feedback instead of a mediocre video.
7. After arbiter PASS, dispatch `../../agents/final-verifier.agent.md` for the mandatory final independent review and verification. A host-native read-only context may be shell-free: capture the verifier's JSON through the host output channel, then run `../../scripts/validate-final-verification.mjs` outside the verifier context so the host deterministically rereads and rehashes every bound artifact. Lack of reviewer shell access is not a blocker when readable inputs and this mandatory post-validator are available. Then run `../../scripts/check-evidence-gate.mjs`.

Acceptance is system-owned: do not use owner watch/listen approval as a recurring release dependency. Approval binds the exact candidate, reports, receipts, policy, arbiter decision, and final verification. Any byte change invalidates it. Deliver only through the mapped OneDrive review root; never copy evidence or video production folders back into the product repository.
