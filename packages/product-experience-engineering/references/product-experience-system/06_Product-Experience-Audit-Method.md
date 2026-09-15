# Product Experience Audit Method

> **Demo/video route:** This modular audit method is supporting depth, not the complete pre-video
> gate. For any workflow intended for recording, run `prepare-product-for-demo` with
> `../product-experience-audit-remediation-guide.md` and emit the validated handoff before Product
> Demo Studio begins.

## Purpose

This method produces a deep understanding of one application and turns that understanding into prioritized, implementable product improvements. It is not a screenshot critique, generic heuristic checklist, or portfolio-wide scan.

The audit begins with the existing product and its users. Agentic behavior is evaluated only when it already exists or when research identifies a workflow where AI or background automation would create specific, testable value. Its absence is not automatically a finding.

## Operating rules

1. Audit one repository at a time.
2. Read repository instructions before running commands or proposing changes.
3. Understand product purpose and workflow before judging visual design.
4. Use realistic synthetic data; never expose secrets or privileged user data.
5. Distinguish observed behavior, source-code evidence, stakeholder intent, and inference.
6. Preserve strong existing patterns and repository-native architecture.
7. Specify broad redesigns before implementing them.
8. Validate implemented behavior through repeatable journeys and visual evidence.

## Phase 1: Establish the product model

### Read

- Root and nested repository instructions.
- README, architecture, product, domain, and roadmap documentation.
- Package manifests, workspace structure, route definitions, schemas, feature flags, and tests.
- Existing design-system, component, copy, analytics, and QA documentation.
- Recent relevant changes when Git history is available.

### Produce

- Product promise and differentiation.
- Primary and secondary users.
- Core jobs, triggers, outcomes, and operating constraints.
- Business model or value exchange where relevant.
- Domain vocabulary and canonical objects.
- Critical workflows and highest-consequence actions.
- Known current limitations and work in progress.

### Gate

Do not begin detailed recommendations until the product can be explained without referring to its file structure.

## Phase 2: Inventory the implemented product

Create linked inventories of:

- routes and navigation;
- screens and major regions;
- user-visible features and actions;
- roles and permissions;
- domain objects and statuses;
- forms, tables, dashboards, documents, and communications;
- integrations and agent/AI capabilities;
- reusable components and tokens;
- empty/loading/error/recovery states;
- automated tests and existing visual evidence.

Mark each feature as complete, partial, hidden, duplicated, obsolete, disabled, or aspirational. Compare documentation with running behavior and code; record mismatches.

## Phase 3: Run the experience

### Environment

Use repository-native setup and commands. Prefer an existing development environment and test data. Confirm authentication personas, feature flags, and integrations. If a live flow is unsafe or unavailable, use read-only inspection or a controlled local substitute and label the limitation.

### Representative journeys

Run at least:

1. First meaningful use.
2. Most frequent core workflow.
3. High-consequence or approval workflow.
4. Search/find/retrieve workflow.
5. Create/edit/submit workflow.
6. Dense operational list or queue.
7. Failure and recovery.
8. Returning to unfinished or completed work.
9. Narrow viewport and keyboard-only journey.
10. Agent/AI workflow when present.

Capture route, persona, data, steps, outcome, friction, screenshots/video where authorized, console/network issues, and state behavior.

## Phase 4: Map workflows and information architecture

For each critical journey, map user, collaborators, application, external systems, and agent activity. Record information needed, decisions, actions, waits, handoffs, workarounds, and exceptions.

Build an information-architecture map from global navigation through objects and local views. Test:

- whether labels match user vocabulary;
- whether frequent destinations are findable;
- whether hierarchy is consistent;
- whether search/filter/navigation overlap sensibly;
- whether users can return to previous context;
- whether related objects and next actions are connected.

## Phase 5: Evaluate product usefulness and feature completeness

Ask of every major capability:

- Which job and outcome does it support?
- Is the workflow complete or does the user leave the product?
- Is required information available at the decision point?
- Are setup and recurring effort proportional to value?
- Are important collaborators and handoffs supported?
- Which workarounds reveal missing utility?
- Which valuable existing features are difficult to discover?
- Which features duplicate one another or create product sprawl?
- Where could automation or AI remove effort without removing judgment?

Identify both defects and opportunities. A product can be usable yet underpowered, or feature-rich yet incoherent.

## Phase 6: Evaluate interaction and visual quality

Use the central principles and patterns to review:

- page purpose and action priority;
- navigation and return context;
- feedback, progress, and state visibility;
- validation, errors, partial completion, and recovery;
- forms, tables, filters, selection, and bulk actions;
- responsive and keyboard behavior;
- content clarity and terminology;
- hierarchy, density, spacing, typography, color, focus, and motion;
- loading continuity and perceived performance;
- agent capability framing, plans, tools, evidence, approvals, and control.

Record evidence at the route, component, and workflow level. “Inconsistent” is not enough; name what differs, why it matters, and which behavior should become canonical.

## Phase 7: Technical feasibility and leverage

Inspect architecture only after the experience need is clear. Determine:

- whether the issue is local or systemic;
- existing components, primitives, state models, and data contracts to reuse;
- missing states or backend capabilities;
- performance and integration constraints;
- migration and compatibility implications;
- test seams and observability;
- whether a small reference implementation can validate the design.

Prefer changes that improve several workflows through one stable abstraction, such as a shared status model, task component, table primitive, or object workspace shell. Avoid unrelated refactoring.

## Phase 8: Write findings

Every finding contains:

1. Title that describes the user problem.
2. User, context, and affected workflow.
3. Observed behavior with route/screen/code evidence.
4. User and product impact.
5. Root cause or contributing factors, labeled as evidence or inference.
6. Recommended experience and why it fits.
7. Scope, dependencies, and affected areas.
8. Validation and success evidence.
9. Priority factors.

### Severity

- **Critical:** prevents the core outcome, causes loss/harm, or makes a consequential action dangerously unclear.
- **High:** frequent or important workflow failure, major missing utility, or severe recovery/accessibility problem.
- **Medium:** meaningful friction, inconsistency, discoverability, or incomplete state affecting productivity/confidence.
- **Low:** localized refinement with limited outcome impact.

Severity is not priority by itself.

### Priority factors

Record user value, frequency/reach, workflow impact, severity, confidence, dependencies, and effort as High/Medium/Low with a one-sentence rationale. Then assign:

- **Now:** required to make the core experience complete or trustworthy.
- **Next:** high-value improvement after prerequisite work.
- **Later:** useful but lower leverage or dependent on future evidence.
- **Do not pursue:** weak product fit, insufficient value, or harmful complexity.

## Phase 9: Create redesign concepts and specifications

Group related findings into coherent experience changes. Define the future workflow and information model before screen details. Use the [Implementation Specification Template](07_Implementation-Specification-Template.md) for each implementable slice.

For broad redesigns, validate sequence, information, terminology, and state behavior through prototypes or a thin reference workflow before rewriting the whole area.

## Phase 10: Implement and validate

Implement in slices that produce an independently usable improvement. For each slice:

1. Add or update repeatable tests for behavior and critical states.
2. Implement using repository-native components and patterns.
3. Inspect realistic sparse, dense, and failure data.
4. Run responsive and keyboard journeys.
5. Capture before/after evidence where useful.
6. Compare the result against specification and success measures.

Do not declare a UX issue fixed because the code changed or one screenshot looks better.

## Phase 11: Feed learning back selectively

After the repository work, classify lessons:

- **Product-specific:** remains in the repository.
- **Domain-specific:** may inform related products but is not universal.
- **Reusable pattern:** update the central system with evidence and examples.
- **Technical-stack-specific:** document with version/freshness context.

This prevents the central reference from becoming a dump of every project decision.

## Audit evidence checklist

- Repository instructions and architecture read.
- Product/user/workflow model documented.
- Route, feature, object, and component inventories completed.
- Critical journeys run or limitation recorded.
- Wide/narrow, keyboard, and failure states inspected.
- Findings link to observable evidence.
- Strengths and existing good patterns preserved.
- Feature opportunities and usability defects both considered.
- Recommendations include scope and validation.
- Broad changes have decision-complete specifications before implementation.
