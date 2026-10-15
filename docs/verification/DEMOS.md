# Demos

Checked 2026-10-15.

## Delivered films

None recorded. The video library root has no AgentHub folder. The notes folder has no AgentHub entry.

## Traces and screenshots

None in the repo. Tracked image files under `packages/` are product-experience-engineering icon assets, not product evidence. The demo fixtures under `packages/product-experience-engineering/tests/fixtures/` belong to that package's own tests; they are not AgentHub demos.

## What a demo could use

- A synthetic profile builder: `scripts/AgentHubDemoProfile.ps1`, runbook `docs/runbooks/demo-profile.md`. It sets `AGENTHUB_OVERLAY=off` (`AgentHubDemoProfile.ps1:143-146`) so the private overlay is not loaded. Its test is `tests/Test-AgentHubDemoProfile.ps1` (not run).
- The showcase report's capture plan and truth labels (the AgentHub runtime report `reports/showcase/agenthub.md`, local). It says: demonstrate now = validate, audit, tests, dispatch list; build next = console, receipts, policy.
- Do not film `global-agent-policy.md`, `overlays/personal`, or host config files with real paths.

## Format status

| Format | Status |
|---|---|
| B. Functional walkthrough | not started (no recording) |
| A. Executive showcase, 60-90 s | not started |
| C. Technical walkthrough | not started |

No recording is a substitute for another; there are none.
