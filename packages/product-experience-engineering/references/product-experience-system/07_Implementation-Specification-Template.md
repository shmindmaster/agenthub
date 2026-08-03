# Implementation Specification Template

## How to use this template

Copy this structure into the active repository for one coherent product improvement. Remove sections that genuinely do not apply, but never omit states, edge cases, or validation merely because the happy path is obvious.

# [Feature or Experience Improvement]

## Summary

State the user problem, target outcome, and proposed experience in three to five sentences.

## Users and context

- Primary user and role:
- Secondary/affected users:
- Trigger and frequency:
- Device/environment:
- Decision authority and permissions:
- Domain constraints:

## Evidence and current behavior

Document the current workflow with route/screen references, observed behavior, usage/support evidence, and source-code locations where relevant. Separate confirmed facts from inference.

### Current workflow

1. [User/system step]
2. [Decision or handoff]
3. [Outcome or failure]

### Current problems

For each problem, state who is affected, what effort/error/uncertainty it creates, and its frequency or consequence.

## Intended outcome and success

### Outcome statement

For **[user/context]**, enable **[job]** so that **[value]**, improving on **[current alternative]** by **[observable difference]**.

### Measures

Define baseline and target direction for relevant measures: completion, time, errors, rework, abandonment, support demand, discovery, repeated use, correction/override, comprehension, accessibility completion, or business result.

### Non-goals

Name adjacent behavior intentionally excluded from this implementation.

## Future workflow

List the complete user/system/agent sequence. Include branching, waiting, collaboration, approval, partial completion, and return.

| Step | Actor | Action/decision | Information required | Result/state |
| --- | --- | --- | --- | --- |
| 1 |  |  |  |  |

## Information model

Define affected objects, relationships, identifiers, display names, lifecycle/status, ownership, timestamps, freshness, provenance, permissions, and authoritative versus proposed/generated state.

### State model

List valid states and transitions. For each transition identify trigger, actor, precondition, side effects, reversibility, and displayed feedback.

## Entry points and discoverability

Specify routes, contextual actions, navigation, search/command access, onboarding, notifications, deep links, and permission-dependent visibility. Explain how first-time and returning users find or resume the feature.

## Screen and component anatomy

For each route, panel, dialog, drawer, or component define:

- purpose;
- title and context;
- decision-relevant information;
- primary and secondary actions;
- layout and hierarchy;
- inputs and validation;
- status/progress;
- evidence/history;
- related objects;
- component reuse or new component responsibility.

Use a small wireframe or flow only when spatial relationships are difficult to specify in prose.

## Interaction behavior

Specify:

- click/tap/keyboard behavior;
- selection and bulk scope;
- save/autosave/draft semantics;
- filters, sort, pagination, and return context;
- focus entry/return;
- pending and disabled behavior;
- cancel, edit, retry, resume, undo, and escape;
- concurrency and stale-data handling;
- navigation with unsaved or running work.

## Agent behavior

When applicable, define:

- capability and scope framing;
- prompt/context construction at a product level;
- plan and stages;
- tools/integrations and read/write boundaries;
- streamed and durable outputs;
- evidence and uncertainty;
- proposal, preview, and approval;
- user input and interruption;
- partial completion and recovery;
- memory scope;
- handoff/escalation.

Do not expose hidden reasoning. Specify concise rationale and decision-relevant evidence.

## Complete state matrix

| State | Trigger | Visible content | Available actions | Persistence/recovery |
| --- | --- | --- | --- | --- |
| First-use empty |  |  |  |  |
| User-created empty |  |  |  |  |
| Filtered empty |  |  |  |  |
| Initial loading |  |  |  |  |
| Background refresh/stale |  |  |  |  |
| Ready/sparse |  |  |  |  |
| Ready/dense |  |  |  |  |
| Pending/running |  |  |  |  |
| Waiting for user/system |  |  |  |  |
| Validation error |  |  |  |  |
| Partial completion |  |  |  |  |
| Expected failure |  |  |  |  |
| Unexpected failure |  |  |  |  |
| Permission denied |  |  |  |  |
| Offline/reconnecting |  |  |  |  |
| Cancelled |  |  |  |  |
| Success |  |  |  |  |

## Content and terminology

Provide exact page titles, primary action labels, statuses, key helper text, confirmations, error messages, empty-state content, and notification language. Define controlled terminology and forbidden ambiguous alternatives.

## Responsive behavior

For narrow, medium, and wide layouts specify:

- navigation and context retained;
- region order and width;
- table/list adaptation;
- primary and bulk actions;
- drawers/dialogs/inspectors;
- document/agent side panels;
- touch and virtual-keyboard behavior;
- content that may be deferred.

## Accessibility and keyboard behavior

Specify semantic structure, accessible names/descriptions, keyboard order and composite-widget model, focus transitions, live announcements, contrast/non-color cues, target sizes, zoom/reflow, reduced motion, screen-reader behavior, and non-drag alternatives.

## Performance and resilience

Define expected response behavior, localized pending UI, background work, timeout/retry, idempotency, cache/staleness, reconnect/resynchronization, and preservation of user work. Include field/lab performance measures when material.

## Permissions, privacy, and sensitive data

Define view/action permissions, scope shown in the UI, redaction, recipient/affected-object confirmation, retention, and safe diagnostic behavior. Backend enforcement remains authoritative.

## Analytics and feedback

Name only events/measures needed to evaluate the intended outcome. Define event trigger, properties, privacy constraints, owner, and decision the data will inform. Include qualitative observation or feedback when analytics cannot explain why users struggle.

## Technical approach

List affected routes, components, data contracts, services, migrations, feature flags, and tests. Reuse repository-native patterns. Explain any new abstraction and which later work may rely on it.

## Edge cases

Enumerate real edge cases: missing/conflicting data, duplicate submission, stale record, changed permission, concurrent edit, integration outage, large volume, partial batch, malformed document, unsupported input, user navigation, refresh/reconnect, and external action failure.

## Acceptance criteria

Write observable behavior in given/when/then form. Cover the primary journey, important branches, all consequential states, responsiveness, keyboard operation, accessibility, and recovery.

## Validation plan

### Automated

List applicable unit, integration, component, accessibility, and repository-native browser journeys with exact commands and expected pass evidence. Use Playwright when it is already supported or is the justified testing choice; do not assume one framework for every repository.

### Manual/visual

List personas, data fixtures, viewport sizes, keyboard/screen-reader checks, failure injection, and screenshots/video required.

### Outcome validation

State how and when the change will be compared with baseline and what result would prompt refinement or rollback.

## Rollout and migration

Define compatibility, existing-data handling, staged exposure, fallback, support/content updates, and removal of replaced behavior. Include rollback only when the repository workflow requires it.

## Decision log

Record meaningful product/UX tradeoffs, evidence, chosen approach, and rejected alternatives so implementation does not reopen settled questions without new evidence.
