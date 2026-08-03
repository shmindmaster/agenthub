---
name: discover-application
description: Use when beginning work in an unfamiliar existing application repository, especially before a product-experience audit, redesign, frontend refactor, or feature-planning effort.
---

# Discover Application

## Overview

Build an evidence-based model of the application before judging or changing it. Separate observed behavior, code evidence, assumptions, and unanswered questions.

## Standalone execution

Start from a bare repository and generate the discovery result during this task. The artifact is
not a prerequisite and the user does not supply it. Return it in the task response by default;
persist `_product-experience/00-discovery.md` only with explicit repository-write authorization.
Follow the bootstrap and consent rules in [artifact contracts](../../references/artifact-contracts.md).

When the user intends to record or demo the workflow, return to `prepare-product-for-demo` after
discovery; discovery alone does not authorize video production.

## Workflow

1. Read repository instructions and inspect current git state. Preserve unrelated work.
2. Run `node ../../scripts/detect-repository-profile.mjs <repository-root>` and `node ../../scripts/inventory-application-surfaces.mjs <repository-root>`.
3. Reconcile scanner leads with documentation, route configuration, navigation, runtime behavior, permissions, external channels, and role-specific access.
4. Inventory every applicable surface family and role using [application surface coverage](../../references/application-surface-coverage.md). Give each a coverage status.
5. Inspect critical screens, data boundaries, tests, analytics, and design-system usage. Run the application with repository-native commands when safe. Use synthetic data only.
6. Map desired outcomes, top tasks, current workflows, failure/recovery paths, constraints, evidence, and unknowns.
7. Return the discovery artifact; if repository persistence was explicitly authorized, write and validate `_product-experience/00-discovery.md` using [artifact contracts](../../references/artifact-contracts.md).

## Reference routing

Read [the routing map](../../references/routing-map.md) and [application surface coverage](../../references/application-surface-coverage.md), then load `00`, `01`, `03`, and `09` from `../../references/product-experience-system/`. Load `02` only if AI behavior is material.

## Evidence rules

| Label | Meaning |
|---|---|
| Observed | Reproduced in the running application |
| Implemented | Confirmed in code or configuration |
| Reported | Stated in repository documentation or by the user |
| Assumed | Plausible but unverified |
| Unknown | Evidence is unavailable |

## Common mistakes

- Do not redesign while still discovering.
- Do not treat route names or component names as proof of user intent.
- Do not inventory every file; follow user-critical journeys.
- Do not conceal missing runtime access or test data.
- Do not omit a surface because it is outside the authenticated product shell.

## Example request

"Understand this application deeply enough to prepare a product-experience audit, without changing it."
