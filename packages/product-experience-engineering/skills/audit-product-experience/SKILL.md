---
name: audit-product-experience
description: Use when an existing application needs a deep usability, utility, workflow, information-architecture, interaction, visual, accessibility, or frontend-experience assessment before changes are selected.
---

# Audit Product Experience

## Overview

Evaluate whether the implemented product helps its users achieve important outcomes clearly, efficiently, safely, and confidently. Produce a prioritized decision artifact, not a cosmetic critique.

## Standalone execution

Start from a bare repository. If `_product-experience/00-discovery.md` is missing or stale, perform
the discovery needed for this audit in memory during the same task; never ask the user to
pre-create it and never persist it without explicit repository-write authorization. Follow
[artifact contracts](../../references/artifact-contracts.md).

For demo or video intent, use `prepare-product-for-demo` as the owning route. This skill remains the
bounded read-only audit stage and must not be mistaken for the full remediation and handoff gate.

## Workflow

1. Read repository instructions and verify or generate discovery context.
2. Build a coverage ledger from [application surface coverage](../../references/application-surface-coverage.md). Include public marketing, acquisition, customer product, customer administration, internal operations, billing, account/security, developer, support, lifecycle communication, and system surfaces when applicable.
3. Give every discovered surface a coverage status, then select high-risk journeys for deep review. Include happy, empty, loading, error, permission, and recovery states.
4. Inspect runtime and implementation evidence. Use the canonical Browser Quality Toolkit's
   `browser-debugging` skill and Chrome DevTools MCP for a dedicated-profile accessibility
   snapshot, console/network evidence, runtime errors, Lighthouse, and performance traces. Use
   repository-owned Playwright for repeatable journeys when it already exists; do not install a
   second browser harness merely for the audit.
5. Evaluate usefulness, feature completeness, workflow coherence, information architecture, feedback, accessibility, responsive behavior, performance perception, and visual hierarchy.
6. Record each finding with ID, severity, evidence, user impact, recommendation, and validation method.
7. Prioritize by user impact, frequency, reach, risk, confidence, and implementation leverage.
8. Return the audit in the task response. If repository persistence was explicitly authorized,
   write `_product-experience/01-audit.md` and validate it with:
   `node ../../scripts/validate-product-experience-artifact.mjs --type audit <file>`

Classify every finding as exactly `product-fix-required`, `capture-fixable`, or `informational`.
Do not use `capture-fixable` for product behavior, accessibility, truth, responsiveness, or
performance defects. Observe and record the first pass before changing code.

## Reference routing

Load [application surface coverage](../../references/application-surface-coverage.md) plus `01`, `03`, `06`, and `09` from `../../references/product-experience-system/`. Add `02` for AI-assisted behavior and `05` for visual-system depth. Follow [artifact contracts](../../references/artifact-contracts.md).

## Severity

| Level | Meaning |
|---|---|
| Critical | Blocks a core outcome, creates serious harm, or destroys trust |
| High | Causes major failure, rework, exclusion, or abandonment |
| Medium | Adds recurring friction or ambiguity with a viable workaround |
| Low | Improves clarity or polish without materially blocking the task |

## Common mistakes

- Do not equate "modern-looking" with useful.
- Do not report preferences without evidence and user impact.
- Do not bury functional defects inside visual-polish notes.
- Do not implement fixes unless the user also authorizes implementation.
- Do not call an audit comprehensive when surfaces are unclassified, shallow, or blocked.

## Example request

"Audit this existing application and tell me what most limits user success and product usefulness."
