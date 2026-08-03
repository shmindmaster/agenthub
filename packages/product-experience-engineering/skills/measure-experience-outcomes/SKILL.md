---
name: measure-experience-outcomes
description: Use when a product-experience change needs baselines, success metrics, instrumentation requirements, qualitative evidence, decision thresholds, or a post-release learning plan.
---

# Measure Experience Outcomes

## Overview

Measure whether users achieve the intended outcome more successfully, not merely whether they click the changed interface.

## Standalone execution

Start from the stated product change, user outcome, available telemetry, and research access. Prior plugin artifacts are not required. If baselines or instrumentation are unavailable, specify how to establish them and label the limitation. Follow [artifact contracts](../../references/artifact-contracts.md).

## Workflow

1. State the product decision and the user outcome it intends to improve.
2. Define the population, journey boundaries, baseline period, and comparison method.
3. Select a small balanced set: task success, time/effort, error/recovery, adoption, retention, trust/satisfaction, and guardrails as relevant.
4. Specify event semantics, properties, privacy constraints, segments, and data-quality checks.
5. Pair behavioral signals with targeted qualitative evidence for "why."
6. Set decision thresholds and actions before results are known.
7. Return the measurement plan in the task response. If repository persistence was explicitly
   authorized, write `_product-experience/06-outcome-measurement-plan.md` and validate it with:
   `node ../../scripts/validate-product-experience-artifact.mjs --type measurement <file>`

## Reference routing

Load `01`, `04`, and `06` from `../../references/product-experience-system/`, plus existing analytics conventions. Follow [artifact contracts](../../references/artifact-contracts.md).

## Metric quality

| Prefer | Avoid alone |
|---|---|
| Successful completion without assistance | Page views |
| Median time and high-percentile time | Average session duration |
| Error recovery and repeat attempts | Button clicks |
| Outcome retention by cohort | Raw feature activation |
| Confidence or trust after consequential work | Generic satisfaction score |

## Common mistakes

- Do not instrument private content when an outcome event is enough.
- Do not change event semantics without migration/versioning.
- Do not claim causality from an uncontrolled before/after comparison.
- Do not add instrumentation code unless implementation is authorized.

## Example request

"Define how we will know whether the redesigned workflow actually reduces user failure and rework."
