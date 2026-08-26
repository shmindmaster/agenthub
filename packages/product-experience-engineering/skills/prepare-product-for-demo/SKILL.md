---
name: prepare-product-for-demo
description: Use when a product or workflow is intended for a demo, screencast, launch video, sales walkthrough, or portfolio showcase and must be audited, remediated, validated, and handed off before any recording or video-production work begins.
---

# Prepare Product for Demo

## Overview

Make the real workflow worth demoing before anyone records it. Execute the smallest complete pre-production pass that can produce an evidence-backed `DEMO-READY`, `REMEDIABLE`, or `DEFERRED` verdict. Fix the product, not the recording.

## Standalone execution

Start from one target repository and the workflows intended for demo. Existing `_product-experience/`
files are optional accelerators, never user prerequisites. Generate or refresh only the artifacts
needed by this pass. Return them in the response unless the user explicitly authorizes repository
persistence. A request for a demo or video is not by itself consent to create plugin working-memory
folders. Follow [artifact contracts](../../references/artifact-contracts.md).

## Required sequence

1. Read repository instructions and preserve unrelated work.
2. Frame each demo workflow: user, job, valuable outcome, current alternative, intended hero moment, and constraints.
3. Establish the product model and inventory the implemented product before judging visual design.
4. Run the actual demo path with realistic synthetic data, including sparse, dense, loading, error, permission, recovery, narrow, zoomed, keyboard, and return/resume states.
   Use the canonical Browser Quality Toolkit for accessibility snapshots, console/network evidence,
   Lighthouse, and performance traces from a dedicated QA profile. Keep the normal personal Chrome
   instance outside the tool boundary.
5. Audit through usefulness, workflow/information architecture, interaction/state completeness, content/trust, visual hierarchy, responsive/accessibility, perceived performance, and conditional agentic behavior.
6. Record evidence-backed findings with severity, priority factors, and `DEMO-BLOCKING yes/no`.
7. Assess all eleven demo-worthiness criteria. Assign `DEMO-READY`, `REMEDIABLE`, or `DEFERRED` before remediation.
8. For `REMEDIABLE`, write decision-complete specifications, implement only within the user's authorized scope, and validate independently useful slices. For `DEFERRED`, do not manufacture a capture workaround.
9. Re-run the eleven criteria against the remediated workflow.
10. Return the demo-readiness handoff and machine-readable payload. Persist
    `_product-experience/07-demo-readiness-handoff.md` and `_product-experience/demo-readiness.json`
    only with explicit repository-write authorization; validate both before a file-based handoff to
    `media-studio` (kind `product-screencast`).

## Video handoff contract

For every workflow provide:

- before and after verdicts;
- the eleven criteria with evidence and failure classification;
- seeded synthetic fixture plus reset command;
- persona and permissions;
- one named hero moment;
- capture-fixable rough edges with exact camera/edit treatment;
- still product-fix-required defects that forbid recording;
- assessed revision, environment, limitations, and confidence.

Apply the final (`afterVerdict`) mapping exactly:

- `DEMO-READY` requires all eleven criteria to pass and maps to `PASS` / `PROCEED`.
- `REMEDIABLE` maps to `FAIL` / `DO-NOT-RECORD`, even when every residual is capture-fixable. Remediate and reassess it before any video work.
- `DEFERRED` maps to `FAIL` / `DO-NOT-RECORD` and must produce no video.

`beforeVerdict` records the workflow's starting state and does not authorize capture. A workflow may begin as `REMEDIABLE` and enter video production only after remediation produces an evidence-backed final `DEMO-READY` verdict.

Validate the Markdown handoff:

```powershell
node ../../scripts/validate-product-experience-artifact.mjs --type demo-handoff _product-experience/07-demo-readiness-handoff.md
```

Validate the machine-readable handoff:

```powershell
node ../../scripts/validate-demo-readiness-handoff.mjs _product-experience/demo-readiness.json --current-revision <revision> --expected-handoff-path _product-experience/07-demo-readiness-handoff.md
```

The two context options are optional, but supply them whenever the caller knows the checked-out revision and expected Markdown handoff path. A mismatch fails validation.

## Reference routing

Read the complete [Product Experience Audit & Remediation Guide](../../references/product-experience-audit-remediation-guide.md). It is the synchronized authoritative guide supplied for this workflow. Use [application surface coverage](../../references/application-surface-coverage.md) and load specialized numbered references only when the workflow needs more depth. Do not replace the guide with the older read-only UI/UX audit route.

## Common mistakes

- Do not start video capture before the handoff validates.
- Do not treat a screenshot or code change as proof that a workflow is fixed.
- Do not downgrade product defects to capture-fixable to keep a schedule.
- Do not expand beyond the demo path unless a shared root-cause abstraction warrants it.
- Do not modify another application repository during the pass.

## Example request

"Prepare these workflows for a product demo, remediate what is authorized, and hand only demo-ready candidates to video production."
