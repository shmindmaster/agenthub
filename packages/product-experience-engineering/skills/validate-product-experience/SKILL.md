---
name: validate-product-experience
description: Use when an implemented application experience, frontend change, workflow, or agentic interaction needs evidence-based functional, usability, accessibility, responsive, and regression validation.
---

# Validate Product Experience

## Overview

Prove the implemented experience works for its intended users and states. Validation is a release decision supported by fresh evidence, not a visual spot-check.

## Standalone execution

Start from the user request, current implementation, diff, tests, and runtime behavior. Prior specification and implementation-log artifacts are helpful but not required. When they are absent, derive explicit expected behavior and label any unresolved product-intent assumptions. Follow [artifact contracts](../../references/artifact-contracts.md).

For demo or video intent, return the evidence to `prepare-product-for-demo`, which alone emits the
product-owned demo-readiness handoff consumed by `media-studio` (kind `product-screencast`).

## Workflow

1. Read the user request, any available specification or implementation log, repository instructions, and changed files.
2. Establish the environment, viewport set, synthetic accounts/data, permissions, and expected outcomes.
3. Run repository-native unit, integration, type, lint, and build checks relevant to the change.
4. Exercise repeatable browser journeys with Playwright when applicable.
5. Verify happy, empty, loading, partial, error, permission, destructive, recovery, refresh, and return-later states in scope.
6. Verify keyboard operation, focus visibility/order/restoration, semantic names, announcements, contrast, zoom/reflow, and reduced motion where applicable.
7. Compare results with acceptance criteria; record reproducible defects and evidence.
8. Return the validation report in the task response. If repository persistence was explicitly
   authorized, write `_product-experience/05-validation-report.md` and validate it with:
   `node ../../scripts/validate-product-experience-artifact.mjs --type validation <file>`

## Reference routing

Load `05` and `06` from `../../references/product-experience-system/`. Add `02` for AI behavior and `08` when an external standard needs primary-source verification. Follow [artifact contracts](../../references/artifact-contracts.md).

## Verdicts

| Verdict | Meaning |
|---|---|
| Pass | Acceptance criteria met with no blocking defects |
| Conditional pass | Useful and safe with documented non-blocking follow-up |
| Fail | A core criterion, critical state, or regression remains broken |
| Blocked | Required environment or evidence is unavailable |

## Common mistakes

- Do not infer runtime behavior from code alone.
- Do not test only one viewport or the happy path.
- Do not downgrade accessibility defects without user-impact reasoning.
- Do not say "validated" when checks were not run.

## Example request

"Validate the implemented workflow and give me a defensible ship/no-ship verdict."
