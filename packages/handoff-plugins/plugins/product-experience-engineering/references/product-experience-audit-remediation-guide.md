# The Product Experience Audit & Remediation Guide
### The pre-production pass: make the product worth demoing before you record it

<!-- version: 1.0 | self-contained edition | companion to demo-video-production-guide.md -->

This guide is standalone and repo-agnostic. It assumes no prompt framework and no shared reference library — everything needed is here. It synthesizes a full product-experience system (principles, application UX patterns, agentic patterns, workflow design method, visual system, audit method, and specification templates) into **one executable pass** that inspects an application, fixes what's wrong, and validates the result.

**Why it exists.** Demo production has a gate that asks: *is this product good enough today to make something worth watching?* When the answer is no, the blockers are almost always product defects — dead time with no feedback, ugly empty states, layout shift, a primary action nobody can find, no single clear outcome. Recording can't hide any of those. This pass runs **before** video production so the demo pipeline has almost nothing left to block on.

**The one principle:** *fix the product, not the recording.* A polished capture of a weak workflow is a lie with good lighting.

---

## How this pairs with demo production

| | This guide | Demo production guide |
|---|---|---|
| Question | Is the product good? | Is the demo compelling and true? |
| Unit of work | A workflow | An episode |
| Output | Working, coherent, polished workflows + an audit record | A killer video, or a product-readiness report |
| When | First | After |

Run this pass over the workflows you intend to demo. Then run demo production. If demo production still returns product-fix-required defects, they come back here as a second, much smaller pass. **Phase 6 is the explicit bridge** between the two.

---

## Operating rules (non-negotiable)

1. **One application at a time.** No portfolio-wide sweep. Don't modify another repository during this pass.
2. **Read repository instructions before running commands or proposing changes.** Root and nested agent/contributor instructions, README, architecture and product docs.
3. **Understand purpose and workflow before judging visual design.** Aesthetics assessed before intent is taste, not evidence.
4. **Use realistic synthetic data.** Never expose secrets, real customer, patient, privileged, or personal data.
5. **Distinguish observed behavior, source-code evidence, stakeholder intent, and inference.** Label which is which in every finding.
6. **Preserve strong existing patterns and repository-native architecture.** Improve within the product's own idiom; don't import a foreign design system or stack because you prefer it.
7. **Specify broad redesigns before implementing them.** Decision-complete spec first (Phase 7).
8. **Findings cite observable behavior and user impact, not personal taste.** "Inconsistent" is not a finding — name what differs, why it matters, and which behavior becomes canonical.
9. **Agentic behavior is conditional.** Evaluate it only where it already exists or where this pass establishes a concrete, testable workflow opportunity. Its absence is not a finding, and "not applicable" is a valid, complete answer.
10. **Don't declare a UX issue fixed because the code changed** or one screenshot looks better.

---

## Scope contract — the demo-critical path first

The failure mode of any audit is unbounded expansion. Bound it explicitly:

- **In scope (always):** the workflows you intend to demo, end to end — entry point, the full happy path, the states around it (empty, loading, error, partial, success), and the return/resume behavior. Plus anything a viewer will see on screen along the way.
- **In scope (conditionally):** a defect outside the demo path that shares a root cause with one inside it. Fixing the shared abstraction once is leverage; chasing every instance is scope creep.
- **Out of scope:** unrelated refactoring, stack migrations, redesigns of areas no demo touches, and "while we're in here" cleanup.

Prefer changes that improve several workflows through one stable abstraction — a shared status model, a table primitive, a task component, an object workspace shell. **Do not propose a platform abstraction merely because several files look similar.**

---

# PHASE 0 — Frame the pass

Before inspecting anything, write down:

- **The workflows to be demoed** (from the demo plan, or your best candidates if the demo isn't scoped yet).
- **The primary user and job** for each: *For [user in context], help them [complete a meaningful job] so that [valuable outcome], improving on [current alternative] by [observable advantage].*
- **The intended hero moment** — the one reveal each demo would be built around. If you can't name it, that's the first finding, and it's a product finding, not a video one.
- **The constraint set:** time available, whether you can change backend, what must not be touched.

If the outcome can't be stated without naming the proposed technology, the framing is too weak — fix that before proceeding.

---

# PHASE 1 — Establish the product model

### Read
Repository instructions (root and nested); README, architecture, product, domain, roadmap docs; package manifests, workspace structure, route definitions, schemas, feature flags, tests; existing design-system, component, copy, analytics, and QA documentation; recent relevant changes in version history.

### Produce
- Product promise and differentiation.
- Primary and secondary users, including approvers, administrators, customers, recipients, and **people represented in the data** (a workflow can work for the operator while harming someone downstream).
- Core jobs, triggers, outcomes, operating constraints.
- Domain vocabulary and canonical objects.
- Critical workflows and highest-consequence actions.
- Known limitations and work in progress.

### Users in operating context
Go past demographics to what actually changes product behavior: responsibilities and decision authority; expertise and vocabulary; volume and repetition; information they possess or lack; collaborators and handoffs; device and physical environment; cost of delay or mistake; accessibility and language needs; incentives, anxieties, and trust boundaries.

### Gate
**Do not begin detailed recommendations until you can explain the product without referring to its file structure.**

---

# PHASE 2 — Inventory the implemented product

Build linked inventories of: routes and navigation; screens and major regions; user-visible features and actions; roles and permissions; domain objects and statuses; forms, tables, dashboards, documents, communications; integrations and any AI/agent capabilities; reusable components and tokens; empty/loading/error/recovery states; automated tests and existing visual evidence.

**Feature inventory** — for each capability record:

| Field | Question |
|---|---|
| User / job | Who uses it, for what outcome? |
| Entry points | Where and how is it discovered? |
| Inputs | What data, documents, permissions, integrations are required? |
| Output | What durable result or state change occurs? |
| Frequency | How often is it used? |
| Workflow relationship | What precedes and follows it? |
| Evidence | Usage, feedback, support issues, tests, stakeholder claims. |
| Completeness | Production-ready / partial / hidden / duplicated / obsolete / aspirational. |

Mark completeness honestly — this is where dormant features, duplicate paths, incomplete promises, and UI-that-exposes-implementation-pieces-instead-of-a-job become visible. Compare documentation against running behavior and code; record mismatches.

---

# PHASE 3 — Run the experience

### Environment
Use repository-native setup and commands. Prefer an existing development environment and test data. Confirm authentication personas, feature flags, and integrations. If a live flow is unsafe or unavailable, use read-only inspection or a controlled local substitute and **label the limitation** — an unrun journey is a confidence gap, not a pass.

### Journeys to run
1. First meaningful use.
2. Most frequent core workflow.
3. High-consequence or approval workflow.
4. Search / find / retrieve.
5. Create / edit / submit.
6. Dense operational list or queue.
7. Failure and recovery (inject failures; throttle the network).
8. Returning to unfinished or completed work.
9. Narrow viewport and keyboard-only.
10. Agent/AI workflow, when present.
11. **The demo path exactly as it would be recorded** — same persona, same seeded data, same sequence, at demo resolution.

Capture per journey: route, persona, data, steps, outcome, friction, screenshots/video where authorized, console and network issues, and state behavior.

---

# PHASE 4 — Evaluate through eight lenses

Each lens names what to look for, the failure modes that matter, and how to gather evidence. Findings from any lens feed Phase 5.

### Lens 1 — Usefulness and feature completeness

Ask of every major capability: which job and outcome does it support? Is the workflow complete, or does the user leave the product? Is required information available *at the decision point*? Are setup and recurring effort proportional to value? Which workarounds reveal missing utility? Which valuable features are hard to discover? Which features duplicate each other?

**Failure modes:** technology-first features with no recurring need; dashboards that display available data without supporting a decision; AI summaries that add reading instead of reducing effort; feature count as a proxy for maturity; a happy path that collapses when a document, party, or approval is missing.

**Classify each observation so the remedy fits the problem:**

| Type | Signal | Likely response |
|---|---|---|
| Missing utility | User can't complete the job or must leave the product | New/expanded capability or integration |
| Workflow friction | Re-entry, excess steps, context switching, waiting | Workflow redesign or automation |
| Information problem | Missing, late, ambiguous, poorly organized context | Information model, IA, or display change |
| Interaction defect | Unclear controls, state, feedback, validation, recovery | Pattern/component behavior change |
| Discoverability | Valuable capability exists but isn't found | Entry point, terminology, onboarding, contextual guidance |
| Trust problem | Can't inspect sources, consequences, or history | Evidence, preview, permissions, activity, recovery |
| Visual coherence | Hierarchy and state hard to scan or inconsistent | Layout, token, typography, density, component refinement |
| Technical constraint | Latency, unreliable integration, stale data | Technical redesign with explicit experience fallback |

**Does a proposed feature deserve to exist?** Evaluate on user value (does it complete or materially improve a real job; is the pain frequent, costly, or risky), product fit (does it strengthen the core promise or create a disconnected tool), feasibility (are data, permissions, integrations available; can failures and exceptions be supported), and adoption (where is it discovered; can value be experienced before extensive setup). Valid decisions: **build, deepen, simplify, integrate, combine, defer, remove.** *"AI-enable" is not a decision category.*

### Lens 2 — Workflow and information architecture

Map each critical journey with swimlanes for user, collaborators, application, external systems, and agent/automation. Include trigger and entry; information gathering; decisions and validation; actions and handoffs; waiting and follow-up; completion and downstream use; exceptions, retries, corrections.

**Do not treat the application boundary as the workflow boundary** — email, spreadsheets, shared drives, calls, printed documents, and memory are part of the current experience. Treating those as user resistance rather than evidence of missing utility is itself a finding.

Per step capture: goal and decision; information needed; system or channel used; manual effort and duplicate entry; wait time and uncertainty; common error or workaround; emotional cost or trust concern.

**Information architecture:** do labels match user vocabulary? Are frequent destinations findable? Is hierarchy consistent? Do search, filter, and navigation overlap sensibly? Can users return to previous context? Are related objects and next actions connected?

**Information model** — good workflows depend on stable concepts. Identify canonical objects and relationships; identity and display name; lifecycle/status model; ownership and permissions; timestamps and freshness; documents, evidence, communications, history; derived values and provenance; and agent-created proposals versus authoritative state. Resolve terminology *before* UI copy: if two teams use different words for one object, decide whether they're synonyms, role-specific views, or genuinely different concepts.

### Lens 3 — Interaction quality and state completeness

The single richest source of demo-blocking defects. Every important surface must distinguish these states — and give each a *specific* answer:

| State | Required answer |
|---|---|
| First-use empty | What belongs here, why it matters, how to create/connect the first item |
| User-created empty | What was removed/completed and the next useful action |
| Filtered empty | Which filters caused no results and how to change them |
| Initial loading | What region is loading; preserve useful prior content when safe |
| Background refresh / stale | When data was last current; how refresh affects work |
| Ready — sparse | Useful at one item, not just at fifty |
| Ready — dense | Scannable at realistic volume |
| Pending / running | Task name, stage, elapsed context, escape |
| Waiting for user or system | What's needed, from whom, and what happens meanwhile |
| Validation error | What input is unusable and how to correct it without losing work |
| Partial completion | What succeeded, what didn't, whether retry is scoped |
| Expected service error | What failed, whether data changed, safest next action |
| Unexpected failure | Stable fallback, diagnostic reference, retry/navigation |
| Permission denied | What's unavailable, why, who can help |
| Offline / reconnecting | What remains available, what's queued, sync status |
| Cancelled | What stopped, what persisted |
| Success | Result, affected object, next step, reversal where applicable |

**Also verify:** state visible near the affected object and preserved across navigation when work continues; determinate progress only when the measure is honest; significant completion confirmed and partial outcomes explained; consequential actions explained before commitment; edit/cancel/pause/retry/resume/undo where the operation genuinely permits them (disable or omit controls the backend can't honor); entered work preserved when validation or submission fails; validation near the field with a linked summary for long forms; one visible saving model (explicit save, autosave, draft-plus-publish, or staged review).

**Failure modes:** a spinner with no task name, stage, or escape; optimistic success that later silently reverses; toast-only feedback for a durable state change; disabling an interface with no explanation; generic "something went wrong"; clearing a form after a server error; confirmation dialogs that repeat the button label instead of the consequence; "undo" offered after an irreversible external action; wizards that discard progress on exit.

### Lens 4 — Content, terminology, and trust

Labels and messages are interface. Verbs describe the actual action; nouns are ones users recognize. State consequence, scope, recipient, or affected count when material. Errors state the problem and the correction. Status labels are a controlled, mutually exclusive set. Distinguish recommendations, estimates, facts, drafts, and completed actions.

**Trust through inspectability:** show source, freshness, assumptions, and scope where they affect a decision; keep durable activity and change history for important workflows; make limitations and unavailable data visible at the point of use; separate model suggestions from authoritative records; enforce permissions outside the presentation layer. Trust comes from reliable behavior, clear limits, evidence, and recovery — not confident tone or trust badges.

**Failure modes:** "Submit," "Process," "Continue," or "AI action" with no context; internal implementation language in user-facing messages; friendly but vague error copy; confidence scores without calibration; citations that don't support the claim; hidden automatic changes.

### Lens 5 — Visual design and hierarchy

Visual design follows the user's decision sequence: *What is this? What state is it in? What needs attention? What supports the decision? What's the primary action? What detail is available?*

- **Hierarchy:** size, weight, position, spacing, contrast, grouping, repetition. A page cannot have five equally prominent primary areas. Don't rely on color alone.
- **Layout:** stable content grid with intentional max widths; a small number of meaningful surfaces rather than nested cards; containment only when it communicates grouping, state, or selection. Responsive behavior defined at **content** breakpoints, not device labels; test compact laptops and zoomed desktops, not only phone and wide monitor.
- **Spacing and density:** documented scale; less space within a group, more between. Density is a product decision — offer comfortable/compact only when both are designed and tested; targets and focus stay adequate in dense modes.
- **Typography:** define roles (display, section heading, object title, body, label, metadata, numeric/tabular, code) rather than a pile of sizes. Tabular numerals for compared columns. Readable measure and line height.
- **Color:** separate brand from semantic. Tokens for background, surface, text, muted text, border, focus, selection, link, accent, status. Every semantic state carries text or iconography in addition to color. Check contrast in *all* states including disabled, selected, hover, dark mode, and charts.
- **Icons and imagery:** reinforce known actions, don't replace unfamiliar language; one family, consistent treatment; ambiguous icons get labels and accessible names. **Do not use generic AI sparkle/robot imagery to imply capability.**
- **Surfaces:** a small hierarchy (app background, work surface, raised/overlay, selected, semantic). Borders for structure, elevation for transient layering, consistent radius. Avoid card-in-card and heavy shadows on static content.
- **Action hierarchy:** primary, secondary, tertiary/ghost, link, destructive — visual priority follows task priority. Destructive actions explicit and separated. Every control needs default, hover, active, focus-visible, disabled, pending, selected, and error states; a pending button keeps its label context, prevents duplicate submission, and **doesn't change width**.
- **Focus, selection, hover:** focus is an interaction state with a highly visible token, distinct from selection and hover. Hover reveals supplemental affordance only — required actions stay available to touch and keyboard.
- **Motion:** explains continuity, hierarchy, entry/exit, progress, or causation. Short and consistent. Never masks unstable layout or implies progress inaccurately. Reduced-motion behavior provided.
- **Tables and dense surfaces:** alignment, whitespace, sticky identity, restrained status tokens. Don't turn every cell into a pill. Row actions predictable, never hover-only discovery.
- **Data visualization:** start from the question the chart answers. Tables for exact comparison, lines for change, bars for categorical comparison. Label values, ranges, units, sources, freshness. Charts link to the records behind the decision.
- **Tokens and ownership:** tokens describe role (`text-muted`, `surface-raised`, `border-danger`, `focus-ring`, `space-section`, `radius-control`), raw scales underneath, semantic tokens above. Own component composition locally; avoid multiple competing component foundations.

### Lens 6 — Responsive, keyboard, and accessibility

Responsive design preserves **task priority**, not the desktop arrangement. Per workflow define: what context stays visible; where navigation moves; how tables and comparison change; where primary and bulk actions live; how drawers/dialogs/inspectors occupy the viewport; how touch targets and virtual keyboards affect forms; what can be deferred without blocking the task.

Accessibility is built into the interaction, not bolted on: semantic structure and established keyboard models; accessible names, descriptions, status announcements, error relationships; focus managed on context change and *not* moved for passive updates; visible focus, sufficient contrast, non-color cues, adequate targets, zoom/reflow, reduced motion; non-drag alternatives; keyboard-complete critical journeys. **Test the composed application, not only the primitives** — custom tables, editors, canvases, and dynamic updates need manual review.

**Failure modes:** clickable `div`s, unlabeled icon buttons, visual-only status; streaming content that steals focus or floods live regions; dialogs that lose the trigger or return focus incorrectly; responsive layouts that hide required actions.

### Lens 7 — Performance and perceived speed

Users experience performance as responsiveness, continuity, and confidence — not raw load time. Render meaningful structure quickly; keep already-useful content visible while refreshing when safe; **localize pending states to the affected region**; avoid layout shift and delayed control movement; permit other work during long background operations.

**Failure modes:** full-page spinners for local updates; skeletons that don't resemble the final layout; buttons with delayed response and no pending state; fast page loads followed by slow blocking interactions.

Inspect load and interaction metrics and request timing, then test perceived responsiveness in the actual critical journey. Acceptance includes visible behavior, not only numeric thresholds.

### Lens 8 — Agentic behavior (conditional module)

**Apply only when AI or background automation already exists or materially improves a validated workflow.** Prefer deterministic behavior when rules are stable and inputs structured. Mark not applicable and move on when there's no useful agentic workflow — that's a valid product decision.

When it applies, evaluate:

- **Capability framing:** can users predict what the agent can do, with what information and authority? Show intended outcome, records in scope, tools it may use, whether it proposes or executes, and what needs approval. Avoid universal "ask anything" framing for a bounded domain.
- **Entry points:** contextual actions on the object being handled ("Summarize this record," "Draft a response"), carrying visible scope the user can edit. Not a floating sparkle button with no predictable purpose.
- **Intent and clarification:** infer reversible low-impact defaults; ask only when ambiguity materially changes result, scope, recipient, cost, or consequence. Summarize the interpreted request before long or consequential work.
- **Editable plans** for multi-stage work: goal, ordered stages in plain language, inputs and exclusions, approval points, controls to edit/reorder/constrain. The plan is the durable outline; don't show a plan execution ignores, and don't expose raw chain-of-thought.
- **Task lifecycle:** explicit states — `draft → ready → queued → running → waiting_for_user | waiting_for_system → completed | partially_completed | failed | cancelled`. Track execution separately from user review. The task must survive closing the panel.
- **Progress:** use the most truthful level available — determinate ("42 of 120"), stage-based, activity-based, then indeterminate with elapsed time and an escape. No fake percentages.
- **Streaming:** stream at a semantic unit; preserve stable layout; distinguish provisional from final; never render half-streamed structured data as authoritative.
- **Tool transparency:** each relevant call as requested → running → succeeded/failed, with human-readable purpose, target system, scope, result. Separate read from write; a write links to the changed object. Never show a successful model message when the underlying write failed.
- **Evidence and provenance:** attach at the smallest useful decision unit — source title/type, stable reference, relevant passage or calculation, source date and retrieval time, scope, whether authoritative/user-provided/inferred/generated, plus conflicts and freshness limits. A citation must support the nearby claim.
- **Uncertainty:** express as concrete reasons (missing document, conflicting values, ambiguous identity) with what would resolve it; prefer action-tied categories over unexplained percentages.
- **Proposals, previews, diffs:** render in the native shape of the result, editable in place, showing additions/removals/recipients/side effects. Regeneration must not silently erase human edits.
- **Approval proportional to consequence:** read/draft runs in visible scope; reversible internal change gets preview and undo; broad or hard-to-reverse change gets explicit review; external communication, money, or legal/clinical/financial consequence gets explicit approval of the final payload, scope, and recipient. Record who approved what version, when.
- **Controls:** pause, cancel, edit, retry, resume, undo — only where the backend genuinely supports them; say so when cancellation is best-effort.
- **Partial completion:** keep successful work, summarize completed/failed/skipped, retry only affected steps. *"12 records updated; 3 skipped because you no longer have edit access"* — not *"the operation failed."*
- **Background work and notifications:** show that work continues, where to find it, how completion is communicated; notifications name the outcome and deep-link to exact context.
- **Memory:** distinguish turn, task, workspace, preference, and long-term memory; show when recalled information affected an output; allow inspect/correct/forget.
- **Handoff:** a packet with goal, context, completed work, evidence, unresolved issue, attempted steps, recommendation — never "contact support" with no retained context.
- **Visual integration:** agent surfaces use the product's own system. Plans, activity, evidence, diffs, and approvals are product components, not a separate visual universe. Avoid excessive avatars, bubbles, gradients, and animation that make operational work feel like a toy.

---

# PHASE 5 — Findings, severity, and priority

### Every finding contains
1. Title describing the **user problem**.
2. User, context, affected workflow.
3. Observed behavior with route/screen/code evidence.
4. User and product impact.
5. Root cause or contributing factors, **labeled evidence or inference**.
6. Recommended experience and why it fits.
7. Scope, dependencies, affected areas.
8. Validation and success evidence.
9. Priority factors.
10. **Demo-blocking flag** (see Phase 6).

### Severity
- **Critical** — prevents the core outcome, causes loss or harm, or makes a consequential action dangerously unclear.
- **High** — frequent or important workflow failure, major missing utility, severe recovery or accessibility problem.
- **Medium** — meaningful friction, inconsistency, discoverability, or incomplete state affecting productivity or confidence.
- **Low** — localized refinement with limited outcome impact.

Severity is not priority by itself.

### Priority factors
Record each as High/Medium/Low with a one-sentence rationale: **user value, frequency/reach, workflow impact, severity, confidence, dependencies, effort and reversibility.** Do not collapse these into a false precise score that hides weak evidence.

Then assign: **Now** (required to make the core experience complete or trustworthy) / **Next** (high value after prerequisites) / **Later** (lower leverage or dependent on future evidence) / **Do not pursue** (weak fit, insufficient value, harmful complexity).

---

# PHASE 6 — The demo-readiness cross-check *(the bridge)*

This is where the audit becomes a pre-production pass. Take each workflow you intend to demo and check it against the eleven demo-worthiness criteria. Any criterion that fails is a **demo-blocking** finding and is automatically **Now** priority for that workflow — regardless of how it scored on general severity.

### Demo-readiness remediation map

| # | Demo-worthiness criterion | Detected by | Typical root cause | Standard remediation |
|---|---|---|---|---|
| 1 | **Single clear outcome** — one visible, valuable result in ≤3 min | Lens 1 | UI exposes implementation pieces rather than a complete job; capability marked partial/hidden; user must leave the product mid-workflow | Complete the workflow inside the product; combine or deepen fragmented capabilities; define feature anatomy end-to-end (entry → decision → action → result → downstream) |
| 2 | **Fast to value** — minimal navigation/setup, no long preamble | Lens 2 | Setup and configuration required before any value; excess handoffs and re-entry | Progressive commitment (explore/draft before full configuration); safe derived defaults; remove duplicate entry; shorten the path to first result |
| 3 | **Clean, believable states** — empty/loading/success/error all presentable | Lens 3 | Only the populated happy path was ever designed | Build the full state matrix; give each empty state a *specific* answer; seed realistic sparse and dense fixtures |
| 4 | **Visual stability** — no layout shift, overflow, clipping | Lens 5 + 7 | Skeletons that don't match final layout; content injected without reserved space; controls that resize on pending | Reserve regions matching final layout; fixed-width pending buttons; test at content breakpoints and zoom |
| 5 | **Legibility** — readable at demo resolution or with reasonable zoom | Lens 5 | Undefined type roles; density without hierarchy; low-contrast metadata | Define typographic roles; tabular numerals in compared columns; verify contrast in all states; restrained containment so dense data reads calmly |
| 6 | **Bounded, feedback-ed waits** — fast, cuttable, or shows progress | Lens 3 + 7 | Spinner with no task name or stage; full-page pending for a local update | Truthful progress (determinate → stage → activity → indeterminate with elapsed time and escape); localize pending to the affected region; keep prior content visible while refreshing |
| 7 | **Discoverable primary action** — findable without tribal knowledge | Lens 2 + 5 | Flat action hierarchy; icon-only controls; action placed away from the information it affects | Establish primary/secondary/tertiary treatments; place the primary action near its object; label ambiguous icons; remove competing emphasis |
| 8 | **Deterministic and resettable** — reseeds and reproduces identically | Lens 1 + technical | No seed/reset path; flaky integration; time- or order-dependent state | Build a reset-and-reseed fixture path; make the flow idempotent; stub or stabilize the flaky dependency with an explicit fallback |
| 9 | **A guardrail is visible** — a trust/safety/human-control moment exists to show | Lens 4 + 8 | No approval boundary; no evidence surface; suggestions indistinguishable from authoritative records | Add approval proportional to consequence; expose evidence/provenance at the decision unit; separate proposal from authoritative state; surface activity history |
| 10 | **A hero moment exists** — one real in-product reveal worth building around | Lens 1 | Product does many small things, none impressive; the hard part is hidden entirely so it reads as trivial | Feature decision — deepen, combine, or integrate to create one leverage moment; surface a *taste* of the work being done so the result reads as earned |
| 11 | **Polish baseline** — consistent theming, nothing visibly unfinished | Lens 5 | Token drift; competing component foundations; one-off values | Consolidate to semantic tokens; standardize repeated component anatomy and states; own composition locally |

### Verdict per workflow
- **DEMO-READY** — all eleven pass. Proceed to video production.
- **REMEDIABLE** — failures exist but are fixable within this pass's constraints. Specify (Phase 7) and fix (Phase 8), then re-check.
- **DEFERRED** — failures require work beyond this pass (architecture, backend capability, integration, or product decision). Write the specification and the evidence, mark the workflow **not demo-ready**, and say so plainly. **A workflow that isn't demo-ready should not be demoed** — that's the whole point of running this first.

---

# PHASE 7 — Specify before implementing

Write a decision-complete specification for every REMEDIABLE finding group and every broad redesign. Group related findings into coherent experience changes rather than isolated screen tweaks. Define the future workflow and information model **before** screen details. Never omit states, edge cases, or validation because the happy path is obvious.

Use the template in **Appendix B**. For broad redesigns, validate sequence, information, terminology, and state behavior with a prototype or a thin reference workflow before rewriting the area.

---

# PHASE 8 — Remediate in slices

Implement in slices that each produce an **independently usable improvement**. For each slice:

1. Add or update repeatable tests for behavior and critical states.
2. Implement using repository-native components and patterns.
3. Inspect realistic sparse, dense, and failure data.
4. Run responsive and keyboard journeys.
5. Capture before/after evidence.
6. Compare the result against the specification and the success measures — not against a screenshot.

**Order of work** (highest demo leverage first):
1. Demo-blocking Critical/High findings on the demo path.
2. Shared abstractions that resolve several demo-blocking findings at once (status model, state components, table primitive, action hierarchy, token consolidation).
3. Remaining demo-blocking findings.
4. Non-blocking Now findings on the demo path.
5. Everything else — only if it fits the scope contract.

Stop expanding when the demo path is DEMO-READY and the shared abstractions are stable. Remaining findings go to the backlog with their specs intact.

---

# PHASE 9 — Validate

### Automated
Unit, integration, component, accessibility, and repository-native browser journeys, with exact commands and expected pass evidence. Use the repository's existing test framework; don't impose one.

### Manual and visual
Personas, data fixtures, viewport sizes (narrow, medium, wide, zoomed), keyboard and screen-reader checks, injected failures, and screenshots/video.

### Visual review as a system
Review together, not in isolation: home/dashboard; dense list or table; object detail/workspace; form or multi-step flow; document/content surface; agent task with plan, progress, evidence, and approval (if applicable); and the empty/loading/error/partial/success states of each. **A polished isolated screenshot is insufficient evidence.**

### Outcome
Compare against baseline for the measures defined in the spec — completion, time, errors, rework, abandonment, support demand, discovery, correction/override, accessibility completion. State what result would prompt further refinement or rollback.

### Demo-readiness re-check
Re-run Phase 6 against the remediated workflows. Record the new verdict per workflow. **This is the artifact demo production consumes.**

---

# PHASE 10 — Hand off and feed learning back

### Handoff to video production
Deliver: the per-workflow demo-readiness verdict; the seeded fixture and reset command that reproduces the demo path; the persona and permissions to use; known remaining rough edges classified as *capture-fixable* (the video pipeline handles with zoom, cut, or spotlight) versus *still product-fix-required* (do not demo this workflow); and the named hero moment per workflow.

### Feed learning back
Classify each lesson: **product-specific** (stays in the repository), **domain-specific** (may inform related products), **reusable pattern** (worth adding to a shared reference, with evidence and examples), or **stack-specific** (document with version and freshness context). Only genuinely generalizable lessons leave the repository — this prevents a shared reference from becoming a dump of every project decision.

---

# APPENDICES

## Appendix A — Audit report skeleton

```
## Metadata
Repository / date / auditor / revision reviewed / environment / personas and data /
areas excluded and why / evidence locations

## Executive assessment
What the application is for, who it serves, strongest qualities, largest barriers to
user value, recommended improvement sequence. Not a list of every finding.

## Product and user model
Product promise · Users and jobs table (user/context | job and outcome |
frequency/consequence | current alternative) · Domain and operating constraints

## Architecture context
Framework, structure, UI/component stack, data/state, auth, integrations, AI runtime,
tests, repository instructions relevant to product changes

## Product inventory
Routes and navigation · Features (capability | user/job | entry point | output |
completeness | evidence) · Domain objects and statuses · Components and patterns

## Critical journey evidence
Per journey: intended outcome · entry point · steps · result · friction/workarounds ·
missing or confusing states · strengths · evidence

## Current-state experience map
User, collaborators, application, external systems, agent — decisions, waiting,
handoffs, re-entry, exceptions

## Strengths to preserve
What already works, why, and where it should become canonical

## Findings
Per finding: user/context · affected workflow and routes · observed behavior ·
evidence · impact · cause (evidence or inference) · recommended experience ·
dependencies/scope · validation · priority · factors · DEMO-BLOCKING yes/no

## Missing product opportunities
Capabilities, integrations, workflow completion, discovery, automation, collaboration
that would materially strengthen the product promise, with evidence

## Experience concepts
Per concept: outcome · users and workflows · future-state sequence · information
architecture · key surfaces · state behavior · why this concept · validation

## Cross-cutting observations
Terminology · status/lifecycle · navigation and shell · forms and validation ·
table/filter/selection · feedback and notifications · permissions · documents and
evidence · agent behavior · tokens/typography/density/color/focus/responsive ·
performance, stale data, reconnect, error boundaries.
For each: the smallest reusable abstraction that improves the affected workflows.

## Demo-readiness cross-check
Per demo workflow: the eleven criteria, pass/fail, blocking findings, verdict
(DEMO-READY / REMEDIABLE / DEFERRED)

## Prioritized roadmap
Now (complete and stabilize the core) · Next (deepen utility) · Later (expand with
evidence) · Do not pursue

## Validation evidence
Automated (commands, scope, result, artifacts) · Manual and visual (personas,
fixtures, viewports, keyboard/screen-reader, failure scenarios) · Outcome (baseline,
observed result, unresolved issues, next decision)

## Limitations and confidence
What couldn't be authenticated, run, populated, or safely exercised; assumptions based
on source rather than behavior; stale evidence; how each affects confidence

## Decision log
Decision | evidence | chosen direction | alternatives rejected | revisit trigger

## Reusable lessons
Classified product-specific / domain-specific / reusable pattern / stack-specific
```

## Appendix B — Implementation specification template

```
# [Feature or Experience Improvement]

## Summary
User problem, target outcome, proposed experience — three to five sentences.

## Users and context
Primary user and role · secondary/affected users · trigger and frequency ·
device/environment · decision authority and permissions · domain constraints

## Evidence and current behavior
Current workflow with route/screen references, observed behavior, usage/support
evidence, source locations. Separate confirmed facts from inference.
Current problems: who is affected, what effort/error/uncertainty, frequency/consequence.

## Intended outcome and success
For [user/context], enable [job] so that [value], improving on [current alternative]
by [observable difference].
Measures with baseline and target direction. Non-goals.

## Future workflow
| Step | Actor | Action/decision | Information required | Result/state |
Include branching, waiting, collaboration, approval, partial completion, return.

## Information model
Objects, relationships, identifiers, display names, lifecycle/status, ownership,
timestamps, freshness, provenance, permissions, authoritative vs proposed state.
State model: valid states and transitions; per transition — trigger, actor,
precondition, side effects, reversibility, displayed feedback.

## Entry points and discoverability
Routes, contextual actions, navigation, search/command access, onboarding,
notifications, deep links, permission-dependent visibility. How first-time and
returning users find or resume it.

## Screen and component anatomy
Per route/panel/dialog/drawer: purpose · title and context · decision-relevant
information · primary and secondary actions · layout and hierarchy · inputs and
validation · status/progress · evidence/history · related objects · component reuse
or new component responsibility.

## Interaction behavior
Click/tap/keyboard · selection and bulk scope · save/autosave/draft semantics ·
filters, sort, pagination, return context · focus entry/return · pending and disabled ·
cancel/edit/retry/resume/undo/escape · concurrency and stale data · navigation with
unsaved or running work.

## Agent behavior (when applicable)
Capability and scope framing · context construction · plan and stages · tools and
read/write boundaries · streamed and durable outputs · evidence and uncertainty ·
proposal, preview, approval · user input and interruption · partial completion and
recovery · memory scope · handoff. Do not expose hidden reasoning.

## Complete state matrix
| State | Trigger | Visible content | Available actions | Persistence/recovery |
(use the seventeen states from Lens 3)

## Content and terminology
Exact page titles, primary action labels, statuses, key helper text, confirmations,
error messages, empty-state content, notification language. Controlled terminology and
forbidden ambiguous alternatives.

## Responsive behavior
Narrow/medium/wide: navigation and context retained · region order and width ·
table/list adaptation · primary and bulk actions · drawers/dialogs/inspectors · side
panels · touch and virtual-keyboard behavior · deferrable content.

## Accessibility and keyboard
Semantic structure, accessible names/descriptions, keyboard order and composite-widget
model, focus transitions, live announcements, contrast and non-color cues, target
sizes, zoom/reflow, reduced motion, screen-reader behavior, non-drag alternatives.

## Performance and resilience
Expected response behavior, localized pending UI, background work, timeout/retry,
idempotency, cache/staleness, reconnect/resync, preservation of user work.

## Permissions, privacy, sensitive data
View/action permissions, scope shown in UI, redaction, recipient confirmation,
retention, safe diagnostics. Backend enforcement remains authoritative.

## Analytics
Only events needed to evaluate the intended outcome: trigger, properties, privacy
constraints, owner, and the decision the data informs.

## Technical approach
Affected routes, components, data contracts, services, migrations, feature flags,
tests. Reuse repository-native patterns; explain any new abstraction.

## Edge cases
Missing/conflicting data, duplicate submission, stale record, changed permission,
concurrent edit, integration outage, large volume, partial batch, malformed document,
unsupported input, user navigation, refresh/reconnect, external action failure.

## Acceptance criteria
Given/when/then observable behavior covering the primary journey, important branches,
all consequential states, responsiveness, keyboard, accessibility, recovery.

## Validation plan
Automated · manual/visual · outcome validation against baseline.

## Rollout and migration
Compatibility, existing-data handling, staged exposure, fallback, support/content
updates, removal of replaced behavior.

## Decision log
Tradeoffs, evidence, chosen approach, rejected alternatives.
```

## Appendix C — The principles as an audit question set

Use as a rapid pass over any screen or workflow; each maps to a lens.

1. **Valuable outcome** — Can I name the user, job, outcome, and current alternative this improves?
2. **Fits real work** — Does the product sequence match the real sequence, including work done outside it?
3. **Primary task unmistakable** — After a glance, can a new user state the page purpose and next action?
4. **System state visible** — Under throttling and injected failure, can the user tell what started, what completed, whether it's safe to leave?
5. **Agency and control** — Can the user change their mind at each stage? Are reversal boundaries honest?
6. **Error prevention and recovery** — Do incomplete, malformed, conflicting, duplicate, stale, and unauthorized inputs preserve work and explain correction?
7. **Progressive disclosure** — Is the common path first without deleting advanced capability? Can frequent users go fast?
8. **Consistent concepts** — One term per concept, one behavior per interaction; exceptions documented and purposeful.
9. **Information at the decision point** — Does the user have to remember data from a previous screen, or open a second tab?
10. **Perceptible speed** — Is pending state localized? Does structure render fast? Any layout shift?
11. **Useful defaults** — Do preferences, filters, columns, and density persist appropriately? Are consequential defaults visible and editable?
12. **Accessibility built in** — Keyboard-complete? Focus visible and correctly managed? Non-color cues? Zoom/reflow?
13. **Clear language** — Can users predict what a button does? Does a status answer "what happened?" and "what now?"
14. **Trust through inspectability** — Can a skeptical user trace a consequential output back to inputs and decisions?
15. **Whole lifecycle** — Empty, sparse, dense, stale, partial, failed, archived, permission-limited, interrupted, returning.
16. **Measured improvement** — Is there a baseline and a result that would confirm, challenge, or reverse the change?

**On conflicts:** principles compete — density helps experts and burdens novices; confirmation prevents harm and creates fatigue; personalization reduces repetition and weakens predictability. Resolve through user, task, frequency, consequence, and evidence — never by declaring one principle absolute. Document the tradeoff in the spec and validate the riskier assumption.

## Appendix D — Acceptance checklists

**Visual acceptance:** page purpose and primary action visually obvious · hierarchy matches decision importance · repeated components and states consistent · dense information scannable · all interactive states including focus and pending designed · responsive layouts preserve task completion · color is not the only meaning carrier · loading and transitions avoid disruptive shifts · agent surfaces feel native · product identity coherent without interfering with utility.

**Core pattern validation:** clear task and page purpose · complete state matrix including partial and recovery · stable navigation and return context · narrow and wide behavior · keyboard and accessible name/focus/status · realistic sparse and dense data · permission, stale-data, and concurrent-change behavior · copy that predicts actions and supports correction · perceived-continuity behavior · agent activity integrated without duplicating canonical state.

**Agentic validation matrix (when applicable):** supported and unsupported request · missing, ambiguous, stale, conflicting context · fast and long-running success · tool failure before and after partial work · user denial or edit at approval · navigate away, refresh, reconnect, return · pause/cancel/retry/resume semantics · concurrent record change · narrow viewport, keyboard-only, screen-reader status · evidence inspection and correction of a result.

**Audit completion:** repository instructions and architecture read · product/user/workflow model evidence-backed · inventories complete · critical journeys run or limitation recorded · wide/narrow, keyboard, and failure states inspected · findings link to observable evidence · strengths documented, not only problems · defects, friction, missing utility, and opportunities all considered · recommendations specify intended behavior and validation · broad changes have specifications · demo-readiness cross-check complete · no other repository modified.

## Appendix E — Optional runnable agent prompt

```
Audit and remediate <PRODUCT> at <REPO_PATH> so that the workflows intended for demo
are demo-ready. Write the audit record and specifications to <REPO_PATH>/<WORK_DIR>/.

Follow this guide's phases. Operating rules are non-negotiable: one repository only;
read repository instructions first; understand purpose and workflow before judging
visual design; realistic synthetic data only; label observation vs inference; preserve
repository-native patterns; specify broad redesigns before implementing; findings cite
observable behavior and user impact, not taste; the agentic module is conditional and
"not applicable" is a valid answer; a code change is not proof a UX issue is fixed.

Scope: the workflows named for demo (<WORKFLOWS>), end to end, plus any defect sharing
a root cause with one of them. No unrelated refactoring or stack migration.

Phase 0 frame the pass (workflows, users, outcome statements, intended hero moment,
constraints). Phase 1 establish the product model — gate: you must be able to explain
the product without referring to its file structure. Phase 2 inventory routes, features
with completeness, objects and statuses, components, states, tests. Phase 3 run the
journeys including the demo path exactly as it would be recorded. Phase 4 evaluate
through the eight lenses. Phase 5 write findings with severity, priority factors, and a
demo-blocking flag. Phase 6 run the demo-readiness cross-check and assign each workflow
DEMO-READY / REMEDIABLE / DEFERRED. Phase 7 write decision-complete specifications for
remediable groups. Phase 8 remediate in independently useful slices, highest demo
leverage first, stopping when the demo path is ready and shared abstractions are stable.
Phase 9 validate automated + manual/visual + outcome, then re-run the cross-check.
Phase 10 produce the handoff and classify reusable lessons.

Return: per-workflow demo-readiness verdict before and after; findings by severity with
demo-blocking flags; what was remediated and the evidence; what was specified but
deferred and why; the seeded fixture, reset command, and persona that reproduce the
demo path; remaining rough edges classified capture-fixable vs still product-fix-
required; named hero moment per workflow; limitations and confidence.
```

## Appendix F — Config checklist

- **`<WORK_DIR>`** — folder in the repository for the audit record, specifications, and evidence.
- **Environment** — repository-native setup and run commands; a working development environment.
- **Personas and permissions** — the roles needed to run each journey.
- **Seed and reset** — a command that reproduces realistic synthetic data deterministically. *This is also what demo production requires; building it here serves both.*
- **Test framework** — whatever the repository already uses.
- **Workflows in scope** — the named demo candidates.
- **Constraints** — what can't be changed (backend, integrations, schedule).

---

## The one line

Demo production asks whether a video is worth watching. This pass makes sure the answer can be yes — by fixing the product's states, hierarchy, feedback, discoverability, and coherence *before* anyone points a camera at it. **Everything a demo cannot hide, fix here.**