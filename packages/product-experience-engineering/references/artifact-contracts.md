# Product Experience Artifact Contracts

## Origin and lifecycle

Product-experience artifacts are generated outputs, not application source. A bare repository is a
valid starting point; the user is never expected to create these files manually.

**Default: do not create or update `_product-experience/`.** Return the useful assessment,
specification, implementation record, validation evidence, or handoff in the task response. Write
these artifacts into the target repository only when the user explicitly authorizes persistent
product-experience artifacts for that repository. Authorization to inspect, audit, implement code,
or produce a demo does not by itself authorize a plugin working-memory folder.

Before a persistent write, name the proposed files and obtain that authorization. When authorized,
keep the minimum durable set; do not create empty stage files, duplicate evidence already owned
elsewhere, or a full lifecycle folder merely because the plugin supports it. Repository
instructions may prohibit or redirect persistence.

For every skill:

1. If a relevant artifact exists, verify that it matches the current repository and request before reusing it.
2. If it is missing or stale, generate the minimum required context from repository and runtime evidence during the current task without persisting it unless explicitly authorized.
3. If the task is narrow, combine outputs in the response or, when persistence is authorized, in the implementation log rather than creating bureaucracy.
4. Never fail only because a prior plugin artifact is absent.
5. Require an approved scope only before consequential implementation. Direct, unambiguous user authorization counts as approval; a separate file does not.

When explicitly authorized, keep durable work inside the target repository under
`_product-experience/` unless repository instructions specify another location. These artifacts
are implementation memory and evidence, not governance gates.

| Stage | Default artifact | Required content |
|---|---|---|
| Discovery | `00-discovery.md` | Users and roles, outcomes, surface inventory, workflows, architecture, constraints, evidence, unknowns |
| Audit | `01-audit.md` | Executive summary, scope and evidence, surface coverage, findings, priorities, risks and unknowns, decision |
| Workflow and feature design | `02-workflow-and-feature-design.md` | Outcome, actors, current and target flows, states, information architecture, acceptance signals |
| Implementation specification | `03-implementation-specification.md` | Scope, behavior, UI states, data and integration effects, accessibility, tests, rollout |
| Implementation | `04-implementation-log.md` | Approved scope, changed files, decisions, migrations, commands and results, residual risks |
| Validation | `05-validation-report.md` | Environment, scenarios, functional results, accessibility, responsive behavior, defects, verdict |
| Measurement | `06-outcome-measurement-plan.md` | Questions, metrics, baselines, instrumentation, segments, decision thresholds, review cadence |
| Demo-readiness handoff | `07-demo-readiness-handoff.md` plus `demo-readiness.json` | Before/after workflow verdicts, eleven criteria with evidence, remediation evidence, seeded fixture and reset command, persona/permissions, hero moment, residual classification, limitations, and the video handoff decision |

Every finding must connect evidence to user impact, a concrete recommendation, and a way to validate the result. Label assumptions and unavailable evidence. Use synthetic data for testing. Do not place secrets, production records, or copied private user content in artifacts.

`media-studio` consumes the demo-readiness handoff for `product-screencast` jobs; it does not own or reconstruct the product-experience assessment. A stale handoff, revision mismatch, missing criterion, missing evidence, or unresolved product-fix-required defect fails closed before capture.

The machine-readable handoff uses its final `afterVerdict` as the video gate. `DEMO-READY` requires all eleven criteria to pass and maps only to `PASS` / `PROCEED`. `REMEDIABLE` and `DEFERRED` both map to `FAIL` / `DO-NOT-RECORD`; neither enters video production. A starting `beforeVerdict` of `REMEDIABLE` is historical context, not permission to record.

When the current repository revision or expected Markdown handoff path is known, validate that context explicitly:

```powershell
node ../../scripts/validate-demo-readiness-handoff.mjs _product-experience/demo-readiness.json --current-revision <revision> --expected-handoff-path _product-experience/07-demo-readiness-handoff.md
```
