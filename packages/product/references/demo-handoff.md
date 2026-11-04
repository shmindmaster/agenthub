# Demo handoff

## Contents

- The eleven criteria
- Verdicts
- Markdown handoff
- JSON handoff

## The eleven criteria

Use each `id` exactly. Any failed criterion blocks the demo and is Now priority for that workflow.

| `id` | Passes when | Standard fix |
|---|---|---|
| `single-clear-outcome` | One visible, valuable result fits in three minutes | Complete the job inside the product |
| `fast-to-value` | Little navigation or setup before value | Safe defaults, draft before configure, remove re-entry |
| `clean-believable-states` | States look finished and realistic data seeds cleanly | Build every state, seed sparse and dense fixtures |
| `visual-stability` | No shift, overflow or clipping on the happy path | Reserve space, matching skeletons, fixed-width pending buttons |
| `legibility` | Key text reads at demo resolution or reasonable zoom | Type roles, contrast in every state, calm density |
| `bounded-feedback-rich-waits` | Each wait is fast, cuttable or shows progress | Truthful progress, pending limited to the affected region |
| `discoverable-primary-action` | Findable without tribal knowledge, no dead ends | Clear action hierarchy, labels, placement near the object |
| `deterministic-resettable` | Reseeds and reproduces identically | Reset command, idempotent flow, stable stub for a flaky dependency |
| `visible-guardrail` | A trust, safety or human-control moment exists to show | Approval sized to consequence, evidence at the decision |
| `hero-moment-exists` | One real in-product reveal is worth building around | Deepen or combine capability to create one |
| `polish-baseline` | Consistent theming, nothing visibly unfinished | Semantic tokens, standard component states |

A multi-second wait with no feedback on a core step is `product-fix-required`. So is having no crisp outcome flow.

## Verdicts

- `DEMO-READY`: all eleven pass.
- `REMEDIABLE`: failures can be fixed in this pass. Fix them and re-score.
- `DEFERRED`: failures need architecture, backend, integration or product decisions. Mark it not demo-ready.

## Markdown handoff

Use these headings, in order:

1. Metadata: assessed revision and environment
2. Workflow verdicts before and after
3. Demo-readiness criteria: the eleven, with evidence
4. Remediation evidence
5. Seed and reset: synthetic fixture and reset command
6. Persona and permissions
7. Hero moments: one per workflow, plus the causal chain from config to action to visible response to result, in one session
8. Remaining rough edges: `capture-fixable` with the exact treatment, and any `product-fix-required`
9. Limitations and confidence
10. Video handoff decision

## JSON handoff

`demo-readiness.json` holds one workflow, an array, or `{ "episodes": [...] }`. Each workflow has:

- `assessmentOwner`: `"product"`
- `episodeId`, `workflow`, `assessedEnvironment`, `assessedRevision`, `persona`, `heroMoment`, `handoffPath`
- `permissions`: at least one
- `seedProfile`: `fixture`, `seedCommand`, `resetCommand`
- `beforeVerdict`, `afterVerdict`, `verdict`, `handoffDecision`
- `criteria`: all eleven, each with `id`, `passed` and `evidence`; a failed one also has `classification`
- `captureFixes`, when any failure is `capture-fixable`
- `productFixes`, when any failure is `product-fix-required`
- `shortestPathToReady`, when `verdict` is `FAIL`

`media-studio` consumes this handoff and fails closed on a stale revision, a missing criterion or an open `product-fix-required` defect.
