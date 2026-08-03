---
name: design-new-application-experience
description: Use when a new application or major greenfield product area needs an outcome-led experience model, feature scope, workflow architecture, interaction system, and implementation-ready first slice.
---

# Design New Application Experience

## Overview

Define a coherent product experience before committing to screens or architecture. Start from users, outcomes, domain objects, and complete workflows.

## Standalone execution

Start from the product idea, available research, and explicit constraints. No `_product-experience/`
files need to exist; generate the useful experience brief, workflow design, and first-slice
specification during this task and return them in the response by default. Follow the persistence
consent rules in [artifact contracts](../../references/artifact-contracts.md).

## Workflow

1. Identify target users, context, jobs, risks, constraints, and evidence quality.
2. Define the product promise and measurable user outcomes.
3. Model domain objects, roles, permissions, lifecycle states, and system boundaries.
4. Prioritize the minimum coherent capability set; distinguish MVP evidence from future breadth.
5. Design navigation, information architecture, primary workflows, cross-workflow continuity, and recovery.
6. Define visual and interaction foundations, accessibility, responsive behavior, and trust requirements.
7. Return an experience brief, target workflow design, and one implementation-ready first-slice specification. Persist them under `_product-experience/` only with explicit repository-write authorization, using [artifact contracts](../../references/artifact-contracts.md).
8. Do not implement unless the user separately authorizes implementation.

## Reference routing

Load `00`, `01`, `03`, `04`, `05`, and `07` from `../../references/product-experience-system/`. Add `02` only when AI materially affects the experience.

## Scope test

| Include now | Defer |
|---|---|
| Capabilities required to complete the core outcome | Adjacent personas and speculative automation |
| Complete states for the primary workflow | Decorative dashboards without decisions |
| Evidence and instrumentation needed to learn | Premature platform generalization |

## Common mistakes

- Do not turn the feature wish list into navigation.
- Do not design only polished happy-path screens.
- Do not treat the first architecture choice as a product requirement.
- Do not confuse an AI-native product with an AI chat box.

## Example request

"Design the first coherent experience for this new application before we choose its screens and components."
