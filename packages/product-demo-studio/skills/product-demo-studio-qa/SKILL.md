---
name: product-demo-studio-qa
description: Use when a proxy or final product-video render needs evidence, truth, persuasion, accuracy, privacy, audio, caption, synchronization, accessibility, frame, playback, or reproducibility validation.
---

# Product Demo QA

QA is a fail-closed release system. Generator self-review is useful but never independent approval.

## Gate

1. Run deterministic technical checks and `../../scripts/preflight.mjs`. Findings conform to `../../schemas/video-finding.schema.json`; preflight binds reports and media to immutable hashes.
2. If preflight passes, dispatch four fresh read-only reviewers with execution receipts:
   - `../../agents/story-experience-reviewer.agent.md`
   - `../../agents/screen-accuracy-compliance-reviewer.agent.md`
   - `../../agents/audio-captions-sync-reviewer.agent.md`
   - `../../agents/technical-frame-integrity-reviewer.agent.md`
3. Validate every report with `../../scripts/validate-review-report.mjs`. Missing, malformed, writable, or non-independent review evidence blocks release.
4. Dispatch `../../agents/release-arbiter.agent.md` in a fresh read-only context. Validate its decision with `../../scripts/validate-release-decision.mjs`.
5. For REMEDIATE, issue the least-privilege assignment, fix only validated findings, render a new candidate, and rerun preflight plus affected reviews. Product and pipeline blockers return explicit feedback instead of a mediocre video.
6. After arbiter PASS, dispatch `../../agents/final-verifier.agent.md` for the mandatory final independent review and verification. Validate with `../../scripts/validate-final-verification.mjs`, then run `../../scripts/check-evidence-gate.mjs`.

Approval binds the exact candidate, reports, receipts, policy, arbiter decision, and final verification. Any byte change invalidates it. Deliver only through the mapped OneDrive review root; never copy evidence or video production folders back into the product repository.

