# Reviewer calibration contract

Calibration proves that independent review is still capable of rejecting known defects and accepting
a clean candidate. It is not a substitute for review and it never lowers the release thresholds in
`policy/product-video-policy.json`.

## Required fixture catalog

Use synthetic, redistributable, immutable fixtures. Each fixture must have a checksum-bound master,
storyboard, transcript, timing-delta report, expected criterion results, and an evidence citation for
the intended result.

| Fixture | Required result | Criterion |
|---|---|---|
| `buried-hero` | fail | `hero-moment-staged` |
| `feature-rung` | fail | `wiifm-rung` |
| `no-hold` | fail | `results-land` |
| `dead-wait` | fail | `bounded-waits` |
| `three-heroes` | fail | `single-hero` |
| `clean-pass` | pass | every applicable criterion |

The clean fixture is mandatory: a reviewer that rejects everything is as broken as one that passes
everything. Add a new fixture whenever a defect reaches the final presentation.

## Execution and provenance

Run calibration after any rubric, reviewer brief, model, evidence format, or input-contract change and
at least every seven days before accepting production review verdicts. Use fresh isolated read-only
reviewer contexts. Reviewers load the canonical rubric and any tightening-only vertical overlay
directly from the installed plugin; do not pass generator reasoning, self-assessment, or rewritten
rubric text through the handoff.

Record the plugin version, rubric and overlay hashes, reviewer/model identifiers, and one immutable
reviewer result per fixture. Each result carries criterion-level outcomes, materialized evidence
citations, and a read-only execution receipt used only as an operational trace. The validator derives the observed
verdict from those criterion results; a hand-authored `observedVerdict` is invalid. Any missing
evidence or receipt is `BLOCKED`, not `PASS`.

The execution receipt must include `inputArtifactSha256` for the fixture input and
`resultPayloadSha256` for the canonical result payload (all review-result fields except the receipt
reference). The validator recomputes both. A valid host receipt cannot be detached from its fixture
or reused to legitimize changed criterion results.

If a known-bad fixture passes, or `clean-pass` fails, return `PIPELINE_BLOCKED`. Treat every production
verdict since the last successful calibration as suspect and rerun affected reviews from immutable
artifacts after the cause is fixed. Diagnose rubric, reviewer brief, model, and input format before
changing a fixture.

This package defines the catalog and enforcement contract. Product repositories may supply their own
additional synthetic fixtures, but vertical overlays may only add criteria or tighten thresholds; they
may never remove a base criterion or weaken the canonical release policy.
