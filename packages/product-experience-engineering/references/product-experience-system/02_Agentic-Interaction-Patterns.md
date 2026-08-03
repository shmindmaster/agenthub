# Agentic Interaction Patterns

## Purpose

Agentic products do more than answer. They investigate, plan, use tools, create artifacts, change records, communicate, wait, fail, and resume. The interface must make that work understandable and controllable without forcing users to read an implementation log.

The default model is an agent embedded in a task-centered workspace. Conversation is useful for intent, clarification, and explanation; structured product surfaces remain better for records, comparisons, forms, approvals, and durable work.

## Applicability boundary

Apply this library only when AI or background automation materially improves a validated user workflow. Start with the user's job, friction, and desired outcome; do not begin with a requirement to add chat, an assistant, or autonomous action. Prefer deterministic application behavior when rules are stable, inputs are structured, and variation adds no user value. When only part of a workflow benefits from AI, keep the rest conventional and use the smallest agentic surface that solves the problem.

During an audit, mark this document **not applicable** when the application has no useful agentic workflow. That is a valid product decision, not a maturity gap.

## 1. Capability and boundary framing

### User need

Users need an accurate mental model of what the agent can do here, with which information and authority.

### Pattern

Describe capabilities through task examples and visible controls. State important exclusions or prerequisites where they become relevant. Before consequential work, show:

- the intended outcome;
- records, date range, account, matter, patient, customer, or project in scope;
- tools or integrations the agent may use;
- whether it can only propose or can execute;
- what requires user input or approval.

### Failure modes

Avoid universal “Ask anything” framing when the agent supports a bounded domain. Do not hide unavailable integrations until after a long run. Do not imply that access to a record means authority to change it.

### Validation

Give representative users several supported and unsupported tasks. They should predict correctly whether the agent can complete them, what input it needs, and whether it will act or only recommend.

## 2. Contextual entry points

### User need

Users should invoke help from the object or workflow they are already handling.

### Pattern

Offer contextual actions such as “Summarize this record,” “Find missing documents,” “Draft a response,” or “Review selected items.” Include a global agent entry only when cross-application tasks are real user needs. Carry visible context into the request and let users remove or add scope before execution.

Entry points should reveal the expected output: a draft, comparison, checklist, proposed change set, completed background task, or answer.

### Failure modes

- A floating sparkle button with no predictable purpose.
- Silent inclusion of the entire workspace when the user selected one record.
- Separate agent actions that duplicate simpler deterministic controls.

## 3. Intent capture and clarification

### User need

The agent needs enough information to act correctly without turning every request into an interview.

### Pattern

Infer reversible, low-impact defaults from visible context. Ask when ambiguity materially changes the result, scope, recipient, cost, or consequence. Prefer structured choices when the answer maps to known options and free text when nuance matters.

Summarize the interpreted request before long or consequential work:

> Review the 18 selected claims, compare them with the policy documents dated through July 2026, and prepare a discrepancy report. Do not update claim status.

Let the user edit scope directly rather than rephrasing the entire request.

### Failure modes

- Asking for information already visible in the workspace.
- Guessing a recipient, jurisdiction, date, or irreversible action.
- Repeated clarification that produces no visible refinement of the task.

## 4. Editable plans for multi-step work

### User need

Users need to inspect and steer how complex work will proceed before investing time or allowing impact.

### When to use

Use a visible plan when work contains several dependent stages, multiple data sources, external actions, significant time/cost, or branching decisions. Skip the ceremony for quick, reversible tasks.

### Anatomy

- Goal and expected artifact or result.
- Ordered stages with plain-language outcomes.
- Inputs, scope, exclusions, and assumptions.
- Approval points and actions that will change state.
- Estimated duration or qualitative effort when meaningful.
- Controls to edit, remove, reorder, or add constraints.

### Behavior

The plan becomes the durable task outline. Updating it changes future work but does not rewrite completed history. Mark completed, active, blocked, waiting, skipped, and changed stages distinctly. If execution must deviate, explain why and request approval when the deviation changes consequence.

### Failure modes

- Displaying a plan that cannot be edited or that execution ignores.
- Exposing internal chain-of-thought instead of useful stages.
- Creating elaborate plans for a one-step answer.

## 5. Task stages and lifecycle

### User need

Users need a stable representation of long-running work across navigation, refresh, and return.

### State model

Use explicit lifecycle states rather than inferring status from text:

`draft → ready → queued → running → waiting_for_user | waiting_for_system → completed | partially_completed | failed | cancelled`

Allow `paused` where the backend can actually suspend work. A task can be completed while its output remains unreviewed; track task execution separately from user review or approval.

### Display

Show the task name, current stage, meaningful recent activity, start/update time, owner, and any required user decision. Keep task history available from the affected workspace and a central task area when background work is common.

### Failure modes

- “Done” when some steps failed.
- Treating “waiting for approval” as running.
- Losing the task when the user closes the chat panel.

## 6. Progress and activity summaries

### User need

Users need confidence that work is advancing and enough detail to diagnose delay without reading raw logs.

### Pattern

Use the most truthful level of progress available:

1. **Determinate:** processed 42 of 120 records.
2. **Stage-based:** collecting, comparing, preparing, waiting.
3. **Activity-based:** searched three sources; reviewing the selected document.
4. **Indeterminate:** working, with elapsed time and a clear escape.

Summarize tools in user language: “Checked the customer ledger” is often more useful than a function name. Offer a details view for IDs, timestamps, queries, or technical diagnostics when needed.

### Accessibility

Do not announce every streamed token or activity event. Use polite live updates for meaningful stage changes, keep focus stable, and let users inspect the activity history on demand.

### Failure modes

- Fake percentages.
- Rapidly changing activity that becomes visual noise.
- A progress indicator that disappears on failure and leaves no explanation.

## 7. Streaming and incremental results

### User need

Users benefit from early useful output when it does not undermine comprehension or stability.

### Pattern

Stream at the semantic unit appropriate to the task: text passages, discovered records, table rows, extracted fields, or completed sections. Preserve stable layout and distinguish provisional from final content. Let users stop generation, continue other work, and understand whether partial output is saved.

For structured outputs, validate chunks before rendering them as authoritative data. Prefer skeletons or reserved regions that match the final layout. Keep finalized sections stable rather than continually rewriting earlier content without indication.

### Failure modes

- Token-by-token animation that slows reading.
- Moving buttons as content grows.
- Treating a half-streamed JSON object as a valid record.
- Hiding a useful prior result behind a full fallback during regeneration.

## 8. Tool activity and integration transparency

### User need

Users need to understand which systems were consulted or changed, especially when results depend on permissions, freshness, or failures.

### Pattern

Represent each relevant tool call through a lifecycle: requested, authorized, running, succeeded, failed, cancelled. Show the human-readable purpose, target system, affected scope, and result summary. Reveal technical arguments only when they help review or diagnosis, and redact secrets or unrelated sensitive data.

Separate read tools from write tools visually and behaviorally. A write result should link to the changed object or show the resulting diff/status.

### Failure modes

- Dumping raw function arguments into the main transcript.
- Hiding a failed source and presenting an incomplete answer as comprehensive.
- Showing a successful model message when the underlying write failed.

## 9. Evidence, citations, and provenance

### User need

Users need to inspect the basis for a claim, recommendation, extraction, or proposed action.

### Evidence model

Attach evidence at the smallest useful decision unit. An evidence item may contain:

- source title and type;
- direct link or stable record reference;
- relevant passage, field, or calculation;
- source date and retrieval time;
- scope or query used;
- whether the source is authoritative, user-provided, inferred, or generated;
- conflicts, missing inputs, or freshness limitations.

Use an evidence drawer or expandable section for detail while keeping critical conflicts visible. A citation must support the nearby claim, not merely mention the same topic.

### Failure modes

- Decorative citation counts.
- Links to search results instead of sources.
- Source snippets with no context or affected claim.
- Mixing verified record data with model inference without labels.

## 10. Uncertainty, confidence, and alternatives

### User need

Users must know where judgment is stable and where review is important.

### Pattern

Express uncertainty through concrete reasons: missing document, conflicting values, low-quality scan, ambiguous identity, outdated record, or model disagreement. Show what evidence would resolve it. Prefer calibrated categories tied to action—“needs review before filing”—over unexplained percentages.

When several plausible interpretations materially change the output, present alternatives and the consequence of each. Do not burden users with uncertainty that does not affect a decision.

### Failure modes

- Precise confidence scores with no calibration.
- Cautious language everywhere, making real warnings indistinguishable.
- Hiding a conflict in a footnote while recommending action confidently.

## 11. Proposals, previews, and diffs

### User need

Before the product changes data or communicates externally, users need to see what will happen.

### Pattern

Render a proposal in the native shape of the result: editable form, message, table changes, document, schedule, or configuration. Show additions, removals, replacements, recipients, affected records, and side effects. Group large diffs and summarize counts without hiding exceptions.

Allow edits in place. Preserve the link between the edited proposal and the eventual action. If the agent regenerates, protect user edits or clearly ask whether to replace them.

### Failure modes

- Approving prose that vaguely describes a hidden payload.
- A diff that omits automatically changed fields.
- Regeneration silently erasing human changes.

## 12. Approval proportional to consequence

### User need

Users need meaningful decision points without confirmation fatigue.

### Decision tiers

| Consequence | Default interaction |
| --- | --- |
| Read, search, summarize, categorize, draft | Run within visible scope; show evidence and result. |
| Reversible internal change | Preview when material; permit undo and show change history. |
| Broad or difficult-to-reverse internal change | Explicit review of affected items and confirmation. |
| External communication, publication, money, legal/clinical/financial consequence | Explicit approval of final payload, scope, recipient, and irreversible effects. |

Approval records should include who approved, what version/payload they saw, scope, time, and resulting action. Permission enforcement belongs in the backend; the interface explains and supports it.

### Failure modes

- A generic “Allow” button with no final payload.
- Requiring approval after the action already occurred.
- Reusing an approval after scope or content changed.
- Asking for repeated confirmation on every harmless read.

## 13. Generative UI and structured artifacts

### User need

Many outcomes are better reviewed and used as interactive product objects than as prose.

### Pattern

Let the agent select among trusted, tested components using validated structured data. Examples include comparison tables, timelines, checklists, document drafts, claim cards, charts, or workflow forms. The component must expose its source, editability, finality, and available actions.

Treat the rendered artifact as a view over typed data. Keep the conversational explanation separate so users can manipulate the object without editing a paragraph. Fall back safely when data is incomplete or the component cannot render.

### Failure modes

- Arbitrary generated layouts that violate design, accessibility, or test expectations.
- A polished card that makes uncertain content look authoritative.
- Components with no way to inspect or export the underlying data.

## 14. Pause, cancel, edit, retry, resume, and undo

### User need

Long and consequential work needs controls that reflect what the system can genuinely do.

### Behavior

- **Pause:** stop at a safe checkpoint and preserve state.
- **Cancel:** terminate future work; explain what already completed.
- **Edit:** change future scope or inputs; identify stages that must be rerun.
- **Retry:** rerun the failed operation with changed conditions or explain why repetition could help.
- **Resume:** continue from a persisted checkpoint after user or system waiting.
- **Undo:** apply a defined compensating action and show its result.

Disable or omit controls the backend cannot honor. If cancellation is best-effort, say so. If an external action is irreversible, offer correction or follow-up rather than false undo.

## 15. Partial completion and recovery

### User need

Users need to retain successful work and understand incomplete work after failures.

### Pattern

Summarize completed, failed, skipped, and uncertain items. Keep usable outputs accessible. Explain the blocking condition, its scope, and the next safe options. Retry only affected steps when possible. For batch work, allow export or review of the successful subset.

Recovery copy should be specific: “12 records updated; 3 were skipped because you no longer have edit access” is actionable. “The operation failed” is not.

### Failure modes

- Rolling back successful independent work without need.
- Marking the whole task failed but hiding useful results.
- Retrying the entire batch and duplicating completed actions.

## 16. Background work and notifications

### User need

Users should be free to leave long-running work and return to a coherent result.

### Pattern

Before leaving, show that the task will continue, where it can be found, and how completion will be communicated. Notifications should describe the outcome or required action, link to the exact task context, and respect user preferences and urgency.

Maintain a task center or contextual history for background work. On return, show what changed since the user left, not the entire activity stream by default.

### Failure modes

- “Your task completed” with no task name or outcome.
- Email and in-app alerts for every stage.
- A notification deep link that opens a generic dashboard.

## 17. Memory and personalization

### User need

Continuity can reduce repetition, but users need control over what is remembered and where it applies.

### Memory layers

- **Turn context:** information needed for the current exchange.
- **Task context:** durable until the task ends or is archived.
- **Workspace context:** shared records and configuration with normal permissions.
- **User preference:** explicit or confidently inferred presentation/behavior choices.
- **Long-term agent memory:** selectively stored facts with provenance, scope, edit, and deletion controls.

Show when recalled information affects an output. Do not store secrets or sensitive facts simply because they appeared in conversation. Let users inspect, correct, forget, or reset durable memory.

## 18. Feedback and correction

### User need

Users need efficient ways to correct the immediate output and improve future behavior when the product supports learning.

### Pattern

Prioritize direct correction: edit the field, replace the source, change the classification, or rerun with a clear constraint. Ask for feedback only when it will influence a product or model decision. Use specific consequences such as “Use this format for future reports” rather than ambiguous approval icons.

Track correction and override as product-quality signals. An accepted output is not necessarily correct; observe later edits and reversals where ethically and technically appropriate.

## 19. Multi-agent and delegated work

### User need

When several specialized agents or workers contribute, the user needs one coherent task model rather than internal orchestration detail.

### Pattern

Present the overall goal, workstreams, ownership, dependencies, and merged result. Show individual workers only when identity explains capability, delay, cost, or a conflict. Resolve duplicate or contradictory outputs before asking the user to inspect them, or present the conflict explicitly with evidence.

Let users stop or change one workstream when independent. Preserve a single approval boundary for the final consequential action even if several agents prepared it.

## 20. Human handoff and escalation

### User need

Some work exceeds the system’s capability, authority, or confidence and must transfer cleanly to a person.

### Pattern

Prepare a handoff packet with the user’s goal, relevant context, completed work, evidence, unresolved issue, attempted steps, and recommended next action. Identify the recipient or queue and expected response behavior. Do not make users repeat the whole story.

### Failure modes

- “Contact support” with no retained context.
- Escalating without permission when sensitive information will be shared.
- Keeping a task in an indefinite waiting state with no owner.

## Conceptual event and state contract

The UI should receive structured events even when the transport or agent framework differs. A minimal conceptual model is:

| Event family | Representative events | UI purpose |
| --- | --- | --- |
| Run | `run.started`, `run.waiting`, `run.completed`, `run.partial`, `run.failed`, `run.cancelled` | Overall task lifecycle and durable status. |
| Step | `step.planned`, `step.started`, `step.progress`, `step.completed`, `step.failed`, `step.skipped` | Plan/stage presentation. |
| Message | `message.started`, `message.delta`, `message.completed` | Streamed conversational content. |
| Tool | `tool.requested`, `tool.started`, `tool.result`, `tool.failed` | Transparent integration activity. |
| Evidence | `evidence.added`, `evidence.conflict`, `evidence.stale` | Claim provenance and review. |
| Artifact | `artifact.created`, `artifact.updated`, `artifact.finalized` | Structured drafts and outputs. |
| Proposal | `proposal.created`, `proposal.edited`, `proposal.invalidated` | Reviewable changes before action. |
| Approval | `approval.requested`, `approval.granted`, `approval.denied`, `approval.expired` | Meaningful decision boundary. |
| Action | `action.started`, `action.succeeded`, `action.partial`, `action.failed`, `action.reversed` | Truthful state-changing outcomes. |
| Input | `input.required`, `input.received`, `input.invalid` | Clarification and waiting. |
| State | `state.snapshot`, `state.delta`, `state.resync_required` | Reconnect and shared-state coherence. |

Every event needs a stable run/task ID, timestamp, type, human-readable summary, and references to affected objects. Consequential events also need actor, scope, payload version, and result. Events must be safe to display; never send secrets or raw hidden reasoning to the frontend.

## Responsive and accessibility requirements

- Keep the primary task and status reachable on narrow screens; move detail into drawers or secondary views without hiding required approvals.
- Preserve keyboard order as streamed content appears.
- Do not focus passive updates; move focus only for user-triggered context change or blocking decisions.
- Announce meaningful stage changes, errors, and completion; avoid token-level live-region output.
- Ensure plans, activity, diffs, evidence, and approval controls work without drag, hover, color, or fine pointer input.
- Respect reduced motion and avoid animation that implies progress inaccurately.

## Validation matrix

Every agentic workflow should test at least:

1. Supported and unsupported request.
2. Missing, ambiguous, stale, and conflicting context.
3. Fast success and long-running success.
4. Tool failure before and after partial work.
5. User denial or edit at approval.
6. Navigation away, refresh, reconnect, and return.
7. Pause/cancel/retry/resume semantics where offered.
8. Concurrent record change.
9. Narrow viewport, keyboard-only use, and screen-reader status behavior.
10. Evidence inspection and correction of an agent result.

Measure whether users understand the scope, can predict action, notice important uncertainty, correct mistakes, recover from failure, and complete the intended job—not merely whether they like the interface.
