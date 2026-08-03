---
name: design-workflows-and-features
description: Use when a product finding, user need, feature idea, or workflow opportunity must become a coherent end-to-end experience with clear utility, information architecture, and interaction states.
---

# Design Workflows and Features

## Overview

Design around the user outcome and the complete task lifecycle. Treat features as capabilities within workflows, not isolated screens or controls.

## Standalone execution

Start from the repository and user request. Prior discovery or audit artifacts are useful accelerators, not prerequisites. If absent, gather the minimum user, workflow, surface, and implementation evidence needed for this design and record it with the output. Follow [artifact contracts](../../references/artifact-contracts.md).

## Workflow

1. State the user, situation, desired outcome, current friction, and evidence.
2. Decide whether to remove, simplify, combine, repair, or add capability.
3. Map the current flow and target flow with entry points, decisions, dependencies, completion, and recovery.
4. Define information architecture, object relationships, navigation, progressive disclosure, and cross-workflow continuity.
5. Specify normal, empty, loading, partial, error, offline, permission, destructive, success, and return-later states where applicable.
6. Define acceptance signals that prove usefulness and usability.
7. Return the workflow design in the task response. Persist `_product-experience/02-workflow-and-feature-design.md` only with explicit repository-write authorization, following [artifact contracts](../../references/artifact-contracts.md).

## Reference routing

Load `01`, `03`, and `04` from `../../references/product-experience-system/`. Add `02` for AI-assisted features and `05` for interaction details.

## Decision test

| Question | Required answer |
|---|---|
| What outcome improves? | A user-observable result |
| Why this capability? | Evidence that simpler options are insufficient |
| What is the shortest complete path? | A coherent path from intent through confirmation |
| What can go wrong? | Explicit prevention and recovery states |
| How will we know? | Testable acceptance and outcome signals |

## Common mistakes

- Do not start with a dashboard or component inventory.
- Do not add AI where deterministic interaction is clearer.
- Do not optimize the happy path while ignoring correction and recovery.
- Do not use feature count as a proxy for utility.

## Example request

"Redesign this onboarding workflow and determine which capabilities genuinely improve activation."
