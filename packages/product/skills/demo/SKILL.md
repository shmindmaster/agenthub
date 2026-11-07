---
name: demo
description: Produces a validated demo-readiness handoff for a real workflow. Use when a product must be ready for a demo, screencast, sales walkthrough or launch before anyone records it. Not for producing the video; use media-studio after this passes.
---

# Demo

## Workflow contract

1. Use the verified revision, demo journey and approved synthetic data.
2. Prove the launch, reset and observed demo actions, then hand the validated demo-readiness package to Media Studio for capture if requested.
3. Return the demo-readiness handoff, artifact paths and open risks.
4. If a role, revision or journey fails, block capture and route the issue back to `verify` or `build`.

Fix the product, not the recording. Start from one repository and the workflows to show; no earlier files are needed. Requires Node.

## Checklist

Copy this list and tick each item.

- [ ] Read the repository's instructions. Stay on the demo path, plus defects that share a root cause with it.
- [ ] For each workflow, name the user, the job, the outcome and one hero moment.
- [ ] Run the real path with synthetic data: sparse, dense, loading, error, permission, recovery, narrow, zoomed, keyboard, return later.
- [ ] Read when a workflow needs a session: [authenticated acceptance](../../references/authenticated-acceptance.md). Prove each role and denial.
- [ ] Score the eleven criteria and record `beforeVerdict` before changing anything.
- [ ] Classify each failed criterion as `product-fix-required` or `capture-fixable`.
- [ ] For `REMEDIABLE`, fix within the authorised scope using `design` and `build`. For `DEFERRED`, stop and say why.
- [ ] Make the product demo-runnable under the [demo harness](../../kits/demo-harness/README.md). Run `node ../../scripts/validate-demo-harness.mjs <repo>` and repeat until it passes.
- [ ] Start the stack in the background with `node ../../scripts/demo-stack.mjs up --repo <repo>`; stop it with `down`.
- [ ] Have `product:reviewer` re-score all eleven criteria from a fresh context. The builder never issues the verdict.
- [ ] Write the handoff and run its validators until both pass.

Read when scoring or writing the handoff: [demo handoff](../../references/demo-handoff.md).

## Rules

- Do not downgrade a product defect to capture-fixable to keep a schedule.
- Do not start capture before the handoff validates because it is only a quick take.
- Do not work around a missing harness item in the edit. It is a product fix.
- Do not change another application repository, even for a shared defect.
- When the hero moment is an approval or an AI decision, build it with [execution controls](../../kits/execution-controls/README.md), so the guardrail on screen is the real one.

## Output

Return the handoff in the response. A demo request is not consent to write files. Save to `_product-experience/07-demo-readiness-handoff.md` and `_product-experience/demo-readiness.json` only when asked. Then run these commands exactly and repeat until both pass:

```powershell
node ../../scripts/validate-artifact.mjs --type demo-handoff _product-experience/07-demo-readiness-handoff.md
node ../../scripts/validate-demo-readiness-handoff.mjs _product-experience/demo-readiness.json --current-revision <revision> --expected-handoff-path _product-experience/07-demo-readiness-handoff.md
```

Next: `media-studio` (kind `product-screencast`), on `DEMO-READY` only.

Read when applying the detailed final mapping, product fix or capture fix. [Workflow detail](references/workflow-detail.md)
