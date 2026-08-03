# Feature and Workflow Design Method

## Purpose

This method prevents two common failures: polishing an experience whose underlying feature is not useful, and adding functionality without understanding how it fits the user’s work. It moves from evidence about people and workflows to a testable product specification.

## 1. Frame the product outcome

Write a one-sentence outcome before discussing screens:

> For **[user in context]**, help them **[complete a meaningful job]** so that **[valuable outcome]**, improving on **[current alternative]** by **[observable advantage]**.

Then define:

- Primary user and other affected people.
- Trigger that starts the work.
- Desired end state.
- Frequency, urgency, and consequence.
- Existing alternative, including work outside the product.
- Constraints: time, device, environment, permissions, domain rules, data, integrations, and collaboration.
- Evidence that the problem exists.

If the outcome cannot be stated without naming the proposed technology, the problem framing is probably too weak.

## 2. Understand users in operating context

Do not stop at demographic personas. Capture what changes product behavior:

- responsibilities and decision authority;
- expertise and vocabulary;
- volume and repetition;
- information they possess or lack;
- collaborators and handoffs;
- device and physical environment;
- cost of delay or mistake;
- accessibility and language needs;
- incentives, anxieties, and trust boundaries.

Separate primary operators from approvers, administrators, customers, recipients, and people represented in the data. A workflow may work well for the operator while creating confusion or harm for someone downstream.

## 3. Build a feature and capability inventory

Inventory what the product already does before proposing additions. For each capability record:

| Field | Question |
| --- | --- |
| User/job | Who uses it and for what outcome? |
| Entry points | Where and how is it discovered? |
| Inputs | What data, documents, permissions, or integrations are required? |
| Output | What durable result or state change occurs? |
| Frequency | How often is it expected to be used? |
| Workflow relationship | What precedes and follows it? |
| Current evidence | Usage, feedback, support issues, tests, or stakeholder claims. |
| Completeness | Production-ready, partial, hidden, duplicated, obsolete, or aspirational. |

This reveals dormant features, duplicate paths, incomplete promises, and areas where the UI exposes implementation pieces rather than a complete job.

## 4. Map the current workflow

Use a sequence with swimlanes for the user, collaborators, product, external systems, and agent/automation. Include:

1. Trigger and entry.
2. Information gathering.
3. Decisions and validation.
4. Actions and handoffs.
5. Waiting and follow-up.
6. Completion and downstream use.
7. Exceptions, retries, and corrections.

For each step capture:

- goal and decision;
- information needed;
- system or channel used;
- manual effort and duplicate entry;
- wait time and uncertainty;
- common error or workaround;
- emotional cost or trust concern;
- evidence available.

Do not treat the application boundary as the workflow boundary. Email, spreadsheets, shared drives, calls, printed documents, and memory are part of the current experience.

## 5. Identify friction and opportunity

Classify observations so the remedy fits the problem:

| Type | Signal | Likely response |
| --- | --- | --- |
| Missing utility | Users cannot complete the job or must leave the product. | New or expanded capability/integration. |
| Workflow friction | Re-entry, excessive steps, context switching, waiting. | Workflow redesign or automation. |
| Information problem | Missing, late, ambiguous, or poorly organized context. | Information model, IA, or display change. |
| Interaction defect | Unclear controls, state, feedback, validation, recovery. | Pattern/component behavior change. |
| Discoverability | Valuable capability exists but is not found or understood. | Entry point, terminology, onboarding, contextual guidance. |
| Trust problem | Users cannot inspect sources, consequences, or history. | Evidence, preview, permissions, activity, recovery. |
| Visual coherence | Hierarchy and state are hard to scan or inconsistent. | Layout, token, typography, density, component refinement. |
| Technical constraint | Latency, unreliable integration, stale data, architecture. | Technical redesign with explicit experience fallback. |

Look for leverage points: one change that removes several downstream steps, one canonical object that reduces re-entry, or one status model that clarifies several screens.

## 6. Decide whether a feature deserves to exist

Evaluate a proposed feature with evidence, not enthusiasm:

### User value

- Does it complete or materially improve a real job?
- Is the pain frequent, costly, risky, or strategically important?
- Does the product have a credible advantage over the current workaround?

### Product fit

- Does it strengthen the product’s core promise?
- Does it deepen a workflow or create a disconnected tool?
- Will users trust this product to perform the job?

### Feasibility and sustainability

- Are the required data, permissions, integrations, and models available?
- Can the product support failures and exceptions?
- Is ongoing maintenance/support proportional to value?

### Adoption

- Where will users discover it?
- What existing behavior must change?
- Can value be experienced before extensive setup?

Possible decisions are: build, deepen, simplify, integrate, combine, defer, or remove. “AI-enable” is not a decision category.

## 7. Design the future-state workflow

Start with the ideal user sequence before arranging screens. Define:

- entry and prerequisite state;
- information shown and collected;
- decisions made by user, system, and agent;
- state-changing actions and approval boundaries;
- collaborators and handoffs;
- background work and return behavior;
- completion, artifact, and next step;
- exception and recovery branches.

Minimize handoffs, re-entry, hidden waiting, and context loss. Preserve valuable human judgment; automate collection, transformation, comparison, and coordination where it reduces effort without obscuring consequence.

Use progressive commitment. Let users explore or draft before requiring full configuration, payment, external communication, or irreversible submission.

## 8. Define the information model

Good workflows depend on stable concepts. Identify:

- canonical objects and relationships;
- identity and display name;
- lifecycle/status model;
- ownership and permissions;
- timestamps and freshness;
- documents, evidence, communications, and history;
- derived values and their provenance;
- agent-created proposals versus authoritative state.

Resolve terminology before UI copy. If two teams use different words for the same object, decide whether they are synonyms, role-specific views, or genuinely different concepts.

## 9. Design feature anatomy and states

For each feature specify:

1. Entry points and discoverability.
2. Preconditions and permissions.
3. Primary view and decision-relevant information.
4. Main and secondary actions.
5. Input and validation.
6. System/agent activity and progress.
7. Review, approval, and commitment.
8. Result, history, and downstream links.
9. Empty, loading, stale, partial, error, interrupted, cancelled, success, and return states.
10. Responsive, keyboard, and accessibility behavior.

Use the [Implementation Specification Template](07_Implementation-Specification-Template.md) when the design is ready for engineering.

## 10. Prioritize opportunities

Prioritization combines evidence and judgment. Record each factor explicitly:

- **User value:** strength of the outcome improved.
- **Frequency/reach:** how often and for whom.
- **Workflow impact:** steps, time, handoffs, uncertainty, or failure removed.
- **Severity:** consequence of the current problem.
- **Strategic fit:** contribution to the product promise.
- **Confidence:** quality of evidence and understanding.
- **Dependencies:** data, architecture, integrations, policy, or preceding UX work.
- **Effort and reversibility:** implementation, migration, support, and ease of learning.

Do not collapse these into a mathematically precise score that hides weak evidence. Use them to explain why one outcome should be addressed before another.

## 11. Define success before implementation

Choose measures that reflect the desired outcome:

- task success and completion quality;
- time and active effort;
- error, rework, correction, or abandonment;
- manual touches and context switches;
- support demand;
- feature discovery and repeated use;
- agent correction, override, false acceptance, and evidence inspection;
- accessibility and keyboard completion;
- perceived ease, confidence, or satisfaction;
- business result directly connected to the workflow.

State baseline, target direction, observation window, and what would cause reconsideration. Analytics should support a decision; avoid collecting sensitive or voluminous interaction data without a purpose.

## 12. Validate before and after building

### Before implementation

- Walk the future workflow with representative users or domain experts.
- Use low-fidelity prototypes for sequence and information decisions.
- Simulate agent success, uncertainty, delay, and failure.
- Review dense and sparse data states.
- Test terminology and action prediction.

### During implementation

- Review real components at responsive widths.
- Test state transitions with synthetic data and injected failures.
- Validate focus, keyboard, screen-reader status, and reduced motion.
- Compare the built behavior with the specification, not only screenshots.

### After implementation

- Run critical journeys with realistic users or proxies.
- Compare outcome measures with baseline.
- Inspect support feedback, corrections, abandonment, and workarounds.
- Refine the product and update central patterns only when the lesson generalizes.

## Feature brief template

### Outcome

For **[user/context]**, enable **[job]** so that **[value]**.

### Evidence

List observations, usage, support cases, workflow artifacts, or research that establish the need.

### Current workflow

Summarize steps, systems, pain, exceptions, and workaround.

### Proposed capability

Describe what becomes possible and how it fits the product promise. Avoid screen-level detail here.

### Future workflow

List user/system/agent steps and decisions, including recovery.

### Scope

Name included and excluded behavior.

### Success

Define observable outcome measures and validation method.

### Open evidence gaps

Name assumptions that must be tested before irreversible architecture or product commitment.
