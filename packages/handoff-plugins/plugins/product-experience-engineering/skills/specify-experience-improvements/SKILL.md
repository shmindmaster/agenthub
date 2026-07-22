---
name: specify-experience-improvements
description: Use when a product finding, workflow design, direct user instruction, or experience direction must become an implementation-ready frontend and interaction specification for a bounded delivery slice.
---

# Specify Experience Improvements

## Overview

Translate an experience direction into a buildable, testable contract. Remove ambiguity without inventing product requirements.

## Standalone execution

Start from the direct user request and repository evidence. A prior audit or design file is not required. If missing, reconstruct the minimum outcome, current behavior, affected surface, and constraints needed for the specification. Follow [artifact contracts](../../references/artifact-contracts.md).

When this specification exists to unblock a demo, return to `prepare-product-for-demo` for
implementation, revalidation, and the revision-bound video handoff.

## Workflow

1. Confirm the source direction or direct instruction and select one coherent delivery slice.
2. Inspect affected routes, components, data contracts, permissions, analytics, tests, and design tokens.
3. Define in-scope and out-of-scope behavior.
4. Specify user flow, UI structure, copy intent, component states, responsive behavior, keyboard behavior, focus, announcements, errors, recovery, and destructive-action safeguards.
5. Identify data, API, migration, telemetry, and compatibility effects.
6. Define functional, interaction, accessibility, visual, and regression acceptance tests.
7. Write `_product-experience/03-implementation-specification.md` and validate it with:
   `node ../../scripts/validate-product-experience-artifact.mjs --type specification <file>`

## Reference routing

Load `04`, `05`, and `07` from `../../references/product-experience-system/`. Add `02` for agentic states and `03` for complex application shells. Follow [artifact contracts](../../references/artifact-contracts.md).

## Specification quality

| Weak | Strong |
|---|---|
| "Improve the form" | Defines fields, grouping, validation timing, error recovery, focus, and success behavior |
| "Make responsive" | Defines layout and priority changes at constrained widths |
| "Add loading state" | Defines trigger, placement, preserved context, cancellation, timeout, and recovery |

## Common mistakes

- Do not specify a whole redesign as one slice.
- Do not prescribe a new library before inspecting repository-native patterns.
- Do not omit non-happy states or validation evidence.
- Do not implement before the specification is approved when approval is required.

## Example request

"Turn finding PX-004 into a specification an engineer can implement without guessing."
