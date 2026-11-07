---
name: audit
description: Produces a prioritised, evidence-labelled assessment of an existing app. Use when asked what works, what is broken, what to fix first, or for a UX, usability or product review of surfaces and journeys. Not for checking a finished change; use verify.
---

# Audit

## Workflow contract

1. Use the requested product surface, target journey, and available evidence.
2. Trace the journey and rank observed issues, then hand the highest-impact issue and evidence to `design`.
3. Return prioritized findings with evidence labels and the next decision.
4. If a surface is inaccessible, record it as blocked and separate assumptions from observations.

Step 1 of 4: ground, decide, build, prove. Change nothing. Start from the bare repository; no earlier files are needed. Requires Node.

## Checklist

Copy this list and tick each item.

- [ ] Read the repository's instructions and `git status`. Work in one repository only.
- [ ] Run `node ../../scripts/detect-repository-profile.mjs <repo>` and `node ../../scripts/inventory-application-surfaces.mjs <repo>`. Confirm their output against navigation, routes and permissions, because both are static guesses.
- [ ] Run the app with the repository's own commands and synthetic data, in a dedicated browser profile. Use the repository's Playwright. If it has none, drive any available browser by hand; do not install a harness.
- [ ] List surfaces and roles, and give each surface a status: `Not applicable`, `Discovered`, `Shallow reviewed`, `Deep reviewed` or `Blocked`.
- [ ] Pick the riskiest journeys. Exercise each through happy, empty, loading, error, permission and recovery states, then by keyboard and at narrow width.
- [ ] Write the findings.
- [ ] Sort findings into Now, Next, Later and Do not pursue, by user value, reach, severity and confidence.

Read when the audit covers more than a few journeys: [surfaces](../../references/surfaces.md).

## Rules

- Do not rate a surface from its code because running it is slow. Code is Implemented, not Observed.
- Do not report a preference as a finding because the alternative looks more modern. Name the behaviour and its user impact.
- Do not call an audit complete to keep it short. List every shallow or blocked surface.
- Do not fix anything here, even a one-line fix.

## Output

Return these sections, in order:

1. Executive summary
2. Scope and evidence
3. Surface coverage
4. Findings, each with ID, severity, evidence label, evidence, user impact, recommendation and how to check the fix
5. Priorities
6. Risks and unknowns
7. Decision

Save to `_product-experience/01-audit.md` only when the user asks for a file. Then run `node ../../scripts/validate-artifact.mjs --type audit <file>`, fix what it reports, and repeat until it passes.

Next: `design`, for the finding you pick.

Read when applying the detailed evidence labels, severity. [Workflow detail](references/workflow-detail.md)
