# Repository Product Experience Audit Template

> **Demo/video route:** Use this template only as supporting audit evidence. The owning executable
> path is `prepare-product-for-demo`, which must complete remediation, rerun all eleven criteria,
> and issue the revision-bound Product Experience handoff before recording.

## Audit metadata

- Repository:
- Audit date:
- Auditor:
- Revision/commit reviewed:
- Environment:
- Personas/data used:
- Areas excluded and why:
- Evidence locations:

Apply the agentic sections only when the application already includes AI behavior or the audit establishes a concrete, testable opportunity for it. Otherwise record them as not applicable and focus on product utility, workflows, features, usability, accessibility, interaction quality, and visual coherence.

## Executive product assessment

Summarize what the application is for, who it serves, its strongest product qualities, the largest barriers to user value, and the recommended improvement sequence. Avoid listing every finding here.

## Product and user model

### Product promise

State the outcome and differentiation in plain language.

### Users and jobs

| User/context | Job and desired outcome | Frequency/consequence | Current alternative |
| --- | --- | --- | --- |

### Domain and operating constraints

Describe vocabulary, permissions, collaboration, devices/environment, data, integrations, time pressure, risk, and accessibility needs that materially affect experience design.

## Architecture and implementation context

Summarize framework, application structure, UI/component stack, data/state architecture, authentication, integrations, AI/agent runtime, tests, and repository instructions relevant to product changes.

## Product inventory

### Routes and navigation

| Route/area | Purpose | Users | Major actions | Status |
| --- | --- | --- | --- | --- |

### Features

| Capability | User/job | Entry point | Output/state change | Completeness | Evidence |
| --- | --- | --- | --- | --- | --- |

### Domain objects and statuses

List canonical objects, relationships, lifecycle, ownership, and terminology conflicts.

### Components and patterns

Inventory application shell, page headers, tables, forms, documents, agent surfaces, feedback, and state components. Identify strong patterns worth preserving.

## Critical journey evidence

For each journey record persona, trigger, data, steps, completion, friction, states, responsive/keyboard observations, and evidence.

### Journey: [Name]

- Intended outcome:
- Entry point:
- Steps:
- Result:
- Friction/workarounds:
- Missing or confusing states:
- Strengths:
- Evidence:

## Current-state experience map

Map the user, collaborators, application, external systems, and agent/automation across the most important workflow. Include decisions, waiting, handoffs, re-entry, and exceptions.

## Strengths to preserve

Document product, workflow, interaction, visual, accessibility, and technical patterns that already work well. Explain why they are effective and where they should become canonical.

## Findings

### [Severity] [Finding title]

- **User/context:**
- **Affected workflow/routes:**
- **Observed behavior:**
- **Evidence:**
- **Impact:**
- **Cause or contributing factors:**
- **Recommended experience:**
- **Dependencies/scope:**
- **Validation:**
- **Priority:** Now / Next / Later / Do not pursue
- **Factors:** user value, frequency, workflow impact, severity, confidence, dependencies, effort.

Repeat the section for each finding. Group by workflow or product area rather than by CSS/component type.

## Missing product opportunities

Describe missing capabilities, integrations, workflow completion, discovery, automation, or collaboration that would materially strengthen the product promise. For each, explain evidence and why existing workarounds are insufficient.

## Experience concepts

Group related findings into coherent future-state concepts. For each concept include outcome, future workflow, information-model changes, major surfaces, agent role, states, and validation approach. Do not jump directly to isolated screen redesign.

### Concept: [Name]

- **Outcome:** What becomes easier, clearer, faster, safer, or newly possible.
- **Users and workflows:** Which journeys and roles change.
- **Future-state sequence:** User, system, collaborator, and agent steps.
- **Information architecture:** New or changed objects, navigation, status, and relationships.
- **Key surfaces:** Routes, workspace regions, forms, tables, documents, agent components, and notifications.
- **State behavior:** Empty, loading, stale, partial, error, interruption, approval, recovery, and success.
- **Why this concept:** Evidence and alternatives considered.
- **Validation:** Prototype, usability scenario, technical spike, or measurable product outcome.

## Cross-cutting system observations

Record issues that affect several workflows and may deserve a shared solution:

- terminology and object naming;
- status/lifecycle inconsistencies;
- navigation and page-shell behavior;
- forms and validation;
- table/filter/selection patterns;
- feedback, progress, and notifications;
- permissions and unavailable actions;
- document/evidence handling;
- agent event, task, proposal, and approval behavior;
- tokens, typography, density, color, focus, and responsive composition;
- performance, stale data, reconnect, and error boundaries.

For each observation, identify the smallest reusable abstraction that improves the affected workflows. Do not propose a platform abstraction merely because several files look similar.

## Prioritized roadmap

### Now: complete and stabilize the core experience

List slices required for a usable, coherent, trustworthy critical workflow.

### Next: deepen utility and efficiency

List high-value capabilities or workflow reductions after prerequisites.

### Later: expand with evidence

List lower-confidence, lower-frequency, or dependency-heavy opportunities.

### Do not pursue

List ideas that weaken product focus, duplicate stronger paths, or add complexity without sufficient value.

## Implementation specifications

Link each approved roadmap slice to a completed [Implementation Specification](07_Implementation-Specification-Template.md) stored in the active repository.

## Validation evidence

### Automated

Record commands, scope, result, and artifacts.

### Manual and visual

Record personas, fixtures, viewports, keyboard/screen-reader checks, failure scenarios, and evidence locations.

### Outcome

Record baseline, observed post-change result, unresolved issues, and next decision.

## Audit limitations and confidence

List areas that could not be authenticated, run, populated, or safely exercised; unavailable personas or integrations; assumptions based on source rather than behavior; and evidence that may be stale. State how each limitation affects confidence and what follow-up would resolve it.

## Decision log

| Decision | Evidence | Chosen direction | Alternatives rejected | Revisit trigger |
| --- | --- | --- | --- | --- |

Use this log for meaningful product and experience tradeoffs, not routine implementation details.

## Reusable lessons

Classify each lesson as product-specific, domain-specific, reusable product pattern, or stack-specific. Propose central-reference updates only for lessons supported beyond this repository.

## Audit completion checklist

- Product/user/workflow model is evidence-backed.
- Running product and source were both inspected where feasible.
- Core, failure, return, responsive, keyboard, and agent journeys were covered.
- Strengths are documented, not only problems.
- Findings distinguish defects, friction, missing utility, and opportunities.
- Recommendations specify intended behavior and validation.
- Broad changes have implementation specifications.
- Repository-native constraints and existing work are preserved.
- No other repository was modified during this audit.
