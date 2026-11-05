---
name: demo
description: Produces a validated demo-readiness handoff for a real workflow. Use when a product must be ready for a demo, screencast, sales walkthrough or launch before anyone records it. Not for producing the video; use media-studio after this passes.
---

# Demo

Fix the product, not the recording. Start from one repository and the workflows to show; no earlier files are needed. Requires Node.

## Checklist

Copy this list and tick each item.

- [ ] Read the repository's instructions. Stay on the demo path, plus defects that share a root cause with it.
- [ ] For each workflow, name the user, the job, the outcome and one hero moment.
- [ ] Run the real path with synthetic data: sparse, dense, loading, error, permission, recovery, narrow, zoomed, keyboard, return later.
- [ ] Score the eleven criteria and record `beforeVerdict` before changing anything.
- [ ] Classify each failed criterion as `product-fix-required` or `capture-fixable`.
- [ ] For `REMEDIABLE`, fix within the authorised scope using `design` and `build`. For `DEFERRED`, stop and say why.
- [ ] Make the product demo-runnable under the [demo harness](../../kits/demo-harness/README.md). Run `node ../../scripts/validate-demo-harness.mjs <repo>`, fix what it reports, and repeat until it passes.
- [ ] Start the stack in the background with `node ../../scripts/demo-stack.mjs up --repo <repo>`; stop it with `down`.
- [ ] Have the `product:reviewer` agent re-score all eleven criteria from a fresh context. The builder never issues the verdict.
- [ ] Write the handoff and run its validators until both pass.

Read when scoring or writing the handoff: [demo handoff](../../references/demo-handoff.md).

## Final mapping

`afterVerdict` is the gate. `beforeVerdict` never authorises recording.

| `afterVerdict` | `verdict` | `handoffDecision` |
|---|---|---|
| `DEMO-READY`, all eleven pass | `PASS` | `PROCEED` |
| `REMEDIABLE`, including when every residual is capture-fixable | `FAIL` | `DO-NOT-RECORD` |
| `DEFERRED` | `FAIL` | `DO-NOT-RECORD` |

## Product fix or capture fix

- `product-fix-required`: behaviour, accessibility, truth, responsiveness or performance.
- `capture-fixable`: a rough edge the camera or edit can treat, with the exact treatment written down.

## Rules

- Do not downgrade a product defect to capture-fixable to keep a schedule.
- Do not start capture before the handoff validates because it is only a quick take.
- Do not work around a missing harness item in the edit. It is a product fix.
- Do not change another application repository, even for a shared defect.
- When the hero moment is an approval or an AI decision, build it with [execution controls](../../kits/execution-controls/README.md), so the guardrail on screen is the real one.

## Output

Return the handoff in the response. A demo request is not consent to write files. Save to `_product-experience/07-demo-readiness-handoff.md` and `_product-experience/demo-readiness.json` only when the user asks. Then run these commands exactly, fix what they report, and repeat until both pass:

```powershell
node ../../scripts/validate-artifact.mjs --type demo-handoff _product-experience/07-demo-readiness-handoff.md
node ../../scripts/validate-demo-readiness-handoff.mjs _product-experience/demo-readiness.json --current-revision <revision> --expected-handoff-path _product-experience/07-demo-readiness-handoff.md
```

Next: `media-studio` (kind `product-screencast`), on `DEMO-READY` only.
