---
name: engineer-product-experience
description: Use when an existing or new application needs broad product-experience improvement and the correct combination of discovery, audit, workflow design, specification, implementation, or validation skills is not already explicit.
---

# Engineer Product Experience

## Overview

Route a request through the smallest complete product-experience workflow. Work on one repository at a time and optimize for useful, implemented improvement rather than documentation volume.

## Standalone execution

Start from a bare repository. `_product-experience/` is optional, explicitly authorized persistent
working memory, not an input the user must provide and not a default output. Apply the bootstrap,
consent, and reuse rules in [artifact contracts](../../references/artifact-contracts.md). Never stop
merely because a prior plugin artifact is absent.

## Route the request

| User intent | Required skills |
|---|---|
| Prepare workflows for demo or video | `prepare-product-for-demo`; it routes the required discovery, audit, specification, implementation, and validation stages |
| Understand or broadly modernize an existing app | `discover-application`, then `audit-product-experience` |
| Improve a known feature or workflow | Minimal `discover-application`, then `design-workflows-and-features` |
| Turn a direction into buildable work | `specify-experience-improvements` |
| Implement a clear, authorized change | `implement-experience-improvements`, then `validate-product-experience` |
| Design a new application | `design-new-application-experience` |
| Design AI-assisted behavior | Add `design-agentic-experiences` |
| Prove post-release value | `measure-experience-outcomes` |

Use the named skill as a required sub-skill. A direct, unambiguous user instruction can supply scope and authorization; a separate approval artifact is not mandatory.

## Subagent workflow

For broad or implementation-bearing work, delegate bounded stages to the shared agent definitions in
`../../agents/`: `experience-auditor.agent.md` establishes current truth,
`experience-designer.agent.md` specifies the approved change,
`experience-implementer.agent.md` owns the implementation, and
`experience-validator.agent.md` performs the final independent review. Combine or skip stages for a
narrow request, but never let the implementer issue the independent validation verdict. Hosts that
do not expose plugin subagents run the same named skills sequentially in fresh contexts.

## Complete-surface rule

For broad existing-app work, inventory every applicable surface, including public marketing, acquisition and identity, the core customer application, customer administration, internal operations, billing, account and security, developer integrations, help and service, lifecycle communications, system recovery, and delivery channels. Use [application surface coverage](../../references/application-surface-coverage.md). Run:

`node ../../scripts/inventory-application-surfaces.mjs <repository-root>`

Treat scanner output as a discovery lead, not proof. Reconcile it with navigation, runtime behavior, permissions, documentation, external channels, and role-specific access. Give every surface a status: `Not applicable`, `Discovered`, `Shallow reviewed`, `Deep reviewed`, or `Blocked`.

## Deliverable behavior

- Generate only artifacts needed to preserve evidence, decisions, specifications, and validation.
- Combine stages for a narrow task when no useful information is lost.
- Label blocked access and unknowns instead of silently omitting surfaces.
- Do not modify multiple application repositories in one run.

## Example request

"Deeply assess and modernize this SaaS application, including its public site, product, administration, and internal operations."
