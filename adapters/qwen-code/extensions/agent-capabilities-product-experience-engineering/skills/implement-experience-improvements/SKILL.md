---
name: implement-experience-improvements
description: Use when a bounded product-experience or frontend improvement has been approved for implementation in an existing repository and its intended behavior is sufficiently specified.
---

# Implement Experience Improvements

## Overview

Implement the smallest complete approved slice while preserving repository conventions, user data, accessibility, and unrelated work.

## Standalone execution

Start from a direct, authorized user instruction or an existing specification. `_product-experience/03-implementation-specification.md` is not inherently required. If it is absent and the request is clear, record a minimal scope, expected behavior, affected states, and validation criteria before coding. If behavior is materially ambiguous, refine it before making divergent product decisions. Follow [artifact contracts](../../references/artifact-contracts.md).

When implementation is part of demo preparation, return to `prepare-product-for-demo`; a code
change without the complete eleven-item recheck is not a video handoff.

## Workflow

1. Read repository instructions, inspect git status, and identify the repo-native build, test, lint, and browser-test commands.
2. Load the authorized scope from the user request or specification and inspect the affected code.
3. Write or update a test that fails for the missing behavior before production code.
4. Implement the minimal complete behavior using existing components, tokens, data patterns, and dependencies when suitable.
5. Cover empty, loading, error, permission, keyboard, responsive, and recovery behavior required by the specification.
6. Run focused tests, then relevant broader checks. Use Playwright for repeatable user journeys when available.
7. Update `_product-experience/04-implementation-log.md` with changed files, decisions, commands and results, and residual risks.

## Reference routing

Load `05` and `07` from `../../references/product-experience-system/`, [artifact contracts](../../references/artifact-contracts.md), the authorized scope, and repository instructions. Load `02` only for agentic behavior.

## Guardrails

- Preserve unrelated changes and never use destructive git recovery commands.
- Use synthetic test data and never expose secrets.
- Do not replace the design system merely to restyle one workflow.
- Do not claim completion without fresh validation evidence.

## Example request

"Implement the approved account-recovery improvement and verify the complete browser journey."
