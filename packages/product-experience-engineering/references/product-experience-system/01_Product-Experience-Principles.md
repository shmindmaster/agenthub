# Product Experience Principles

## How to use these principles

These principles are evaluation and design tools. Apply them to a user journey, feature, screen, or component in context. A product can satisfy a principle in one workflow and violate it in another. Findings should cite observable behavior and user impact, not personal taste.

## 1. Create a valuable outcome

### Intent

The product exists to help a specific person achieve a meaningful result. Features, screens, and AI capabilities are valuable only when they improve that result.

### Requirements

- Name the primary user, job, desired outcome, and current alternative.
- Connect every major feature to a user or business outcome.
- Define what becomes faster, easier, more accurate, more understandable, or newly possible.
- Prefer a complete high-value workflow over many disconnected capabilities.

### Failure modes

- Technology-first features with no recurring user need.
- Dashboards that display available data without supporting a decision.
- AI summaries that add reading instead of reducing effort.
- Feature count used as a proxy for product maturity.

### Audit and evidence

Ask users what they came to accomplish and whether the product helped. Trace the critical workflow from entry to result. Evidence includes task completion, retained usage, reduced manual work, fewer handoffs, or a previously impossible outcome.

## 2. Fit the user’s real work

### Intent

The product should match the user’s vocabulary, information, sequence, constraints, collaboration, and exception patterns.

### Requirements

- Model the actual workflow, including work outside the application.
- Preserve domain terms users understand; explain internal or technical language.
- Support exceptions and incomplete information rather than assuming an ideal path.
- Show the context needed to make the current decision.

### Failure modes

- Forcing users to translate their work into the software’s data model.
- Treating email, spreadsheets, paper, or phone calls only as user resistance instead of evidence of missing utility.
- A “happy path” that collapses when a document, party, or approval is missing.

### Audit and evidence

Map the current workflow with people, systems, inputs, decisions, outputs, delays, and workarounds. Compare the product sequence to the real sequence and count context switches or re-entry.

## 3. Keep the primary task unmistakable

### Intent

At any moment, the user should understand where they are, what matters, and what useful action is available.

### Requirements

- Establish one clear page purpose and information hierarchy.
- Place the primary action near the information it affects.
- Separate routine actions from destructive or infrequent administration.
- Use progressive disclosure for complexity that is not needed yet.
- Let dense operational screens be dense when scanning and comparison require it; remove ornamental noise rather than useful information.

### Failure modes

- Several buttons with equal emphasis and unclear consequences.
- Decorative cards, gradients, badges, or AI panels competing with the work.
- Important exceptions buried below generic metrics.
- Over-minimal interfaces that hide necessary context and controls.

### Audit and evidence

Ask a new user to explain the page purpose and next action after a short glance. Inspect the page at narrow and wide widths. Verify that visual prominence matches task importance.

## 4. Make the system state visible

### Intent

Users need timely, truthful feedback about what is happening, what changed, and what requires attention.

### Requirements

- Distinguish idle, pending, running, waiting, completed, partially completed, failed, cancelled, and stale states.
- Put status near the affected object and preserve it across navigation when the work continues.
- Use determinate progress only when the measure is honest; otherwise show stages, activity, and elapsed context.
- Confirm significant completion and explain partial outcomes.

### Failure modes

- A spinner with no task name, stage, or escape.
- Optimistic success that later silently reverses.
- Toast-only feedback for a durable state change.
- Disabling an interface with no explanation.

### Audit and evidence

Throttle network and inject failures. Verify that the user can tell whether an action started, whether it is safe to leave, what completed, and what to do next.

## 5. Preserve agency and control

### Intent

People should be able to start, steer, inspect, stop, and recover from product and agent activity in proportion to its consequence.

### Requirements

- Explain consequential actions before commitment.
- Provide edit, cancel, pause, retry, resume, undo, or escalation where the underlying operation permits them.
- Avoid locking users into guided modes when direct access is safe.
- Keep approval separate from recommendation and execution.
- Show what cannot be reversed.

### Failure modes

- Confirmation dialogs that repeat the button label without consequences.
- “Undo” offered after an irreversible external action.
- Autonomous actions hidden behind vague settings.
- Wizards that discard progress when exited.

### Audit and evidence

Test changing one’s mind at each stage. Verify cancellation semantics, persisted drafts, reversal boundaries, and the user’s understanding of who or what initiated the action.

## 6. Prevent errors, then support recovery

### Intent

Good products reduce avoidable mistakes and make the remaining mistakes inexpensive to understand and correct.

### Requirements

- Use constraints, sensible defaults, previews, examples, and contextual guidance before errors occur.
- Accept harmless input variation.
- Preserve entered work when validation or submission fails.
- Explain what happened, what remains safe, and how to recover.
- Place validation near the field and summarize errors when the form is large.

### Failure modes

- Generic “invalid input” or “something went wrong” messages.
- Clearing a form after a server error.
- Validating while a user is still typing without a demonstrated need.
- Requiring confirmation for routine, easily reversible actions while failing to protect irreversible ones.

### Audit and evidence

Submit incomplete, malformed, conflicting, duplicate, stale, and unauthorized inputs. Confirm that focus, copy, retained data, and next actions support recovery.

## 7. Reveal complexity progressively

### Intent

New users need a clear starting point; experienced users need depth and efficiency. The interface should reveal advanced capability as it becomes relevant.

### Requirements

- Present the common path first without deleting advanced capability.
- Group advanced filters, metadata, diagnostics, and configuration meaningfully.
- Remember user-chosen views and density where appropriate.
- Provide shortcuts, bulk actions, and command surfaces for frequent users.
- Make hidden capability discoverable through context, not mystery icons.

### Failure modes

- Every setting shown at once.
- Essential fields hidden behind “advanced.”
- Separate “simple” and “expert” modes that drift into different products.
- Icon-only controls with no label or predictable location.

### Audit and evidence

Compare first-time and frequent-user journeys. Measure steps for common tasks and inspect whether advanced actions can be found without documentation.

## 8. Use consistent concepts and behaviors

### Intent

Consistency lets people transfer learning and predict results. It is semantic and behavioral, not merely visual.

### Requirements

- Use one term for one concept and one component behavior for the same interaction.
- Standardize common states, action placement, selection, filtering, saving, and confirmation.
- Keep product-specific identity while reusing stable primitives and tokens.
- Document intentional exceptions and make their purpose visible.

### Failure modes

- “Client,” “customer,” and “account” used for the same entity.
- Some edits autosave while visually identical edits require submission.
- Identical colors or icons representing different states.
- Component reuse that forces unrelated workflows into the same anatomy.

### Audit and evidence

Create an inventory of labels, actions, statuses, and repeated components. Compare behavior across routes and responsive widths.

## 9. Design information for recognition and decision

### Intent

The interface should reduce memory burden and help users compare, prioritize, and decide.

### Requirements

- Show names, status, recency, ownership, and decision-relevant context where choices are made.
- Prefer recognizable labels and previews to identifiers alone.
- Preserve filters, selection, scroll, and return context.
- Use tables for comparison, lists for sequences or summaries, and detail views for depth.
- Surface exceptions and changes, not only totals.

### Failure modes

- Requiring users to remember data from a previous screen.
- Dense cards that cannot be compared.
- Truncated identifiers with no reveal or copy action.
- Status conveyed only by color.

### Audit and evidence

Observe whether users open multiple tabs, copy information elsewhere, or repeatedly navigate back. Test scanning for priority items and comparing alternatives.

## 10. Make speed perceptible and interaction responsive

### Intent

Users experience performance through responsiveness, continuity, and confidence—not only raw load time.

### Requirements

- Render meaningful structure or content quickly.
- Keep already useful content visible while refreshing when safe.
- Localize pending states to the action or region affected.
- Avoid layout shifts and delayed control movement.
- Permit other work during long-running background operations.
- Measure both field performance and workflow completion.

### Failure modes

- Full-page spinners for local updates.
- Skeletons that do not resemble final layout.
- Buttons with delayed response and no pressed/pending state.
- Fast page loads followed by slow, blocking interactions.

### Audit and evidence

Inspect LCP, INP, CLS, request timing, and slow-device behavior, then test perceived responsiveness in the actual critical journey. Performance acceptance should include visible behavior, not only numeric thresholds.

## 11. Provide useful defaults and remember intent

### Intent

Defaults should reduce repetitive work without surprising users or hiding important decisions.

### Requirements

- Derive defaults from the current workflow, role, prior explicit choice, or safe domain convention.
- Make consequential defaults visible and editable.
- Persist stable preferences such as density, columns, saved views, or notification choices.
- Distinguish temporary session context from durable preference or agent memory.

### Failure modes

- Resetting filters and view configuration on every visit.
- Prefilling high-impact choices that users overlook.
- Remembering sensitive context without clear scope.
- Personalization that prevents users from finding the canonical information architecture.

### Audit and evidence

Repeat common work across sessions and roles. Verify default provenance, editability, persistence, reset behavior, and privacy expectations.

## 12. Build accessibility into the interaction

### Intent

The product should remain understandable and operable across input methods, perception modes, zoom levels, devices, and assistive technologies.

### Requirements

- Use semantic HTML and established keyboard interaction models.
- Provide accessible names, descriptions, status announcements, and error relationships.
- Manage focus when context changes; avoid moving it for passive updates.
- Ensure visible focus, sufficient contrast, non-color cues, adequate targets, zoom/reflow, and reduced-motion behavior.
- Provide non-drag alternatives and keyboard-complete critical journeys.
- Test the composed application, not only primitives.

### Failure modes

- Clickable `div` elements, unlabeled icon buttons, or visual-only status.
- Streaming content that continuously steals focus or floods live regions.
- Dialogs that lose the trigger or return focus incorrectly.
- Responsive layouts that hide required actions.

### Audit and evidence

Run keyboard-only workflows, zoom/reflow checks, automated scans, and targeted screen-reader review. Verify custom tables, editors, canvases, agent activity, and dynamic updates manually.

## 13. Use clear, specific product language

### Intent

Content is part of the interface. Labels and messages should help the user predict outcomes and recover without interpretation.

### Requirements

- Use verbs that describe the actual action and nouns users recognize.
- State consequences, scope, recipient, or affected count when material.
- Explain errors in plain language with a corrective next step.
- Keep status labels mutually exclusive and understandable.
- Distinguish recommendations, estimates, facts, drafts, and completed actions.

### Failure modes

- “Submit,” “Process,” “Continue,” or “AI action” without context.
- Internal implementation language in customer-facing messages.
- Friendly but vague error copy.
- Overlong instructional prose replacing a well-designed workflow.

### Audit and evidence

Review labels outside their screen context. Test whether users can predict what a button does and whether a status answers “what happened?” and “what now?”

## 14. Earn trust through inspectability

### Intent

Trust comes from reliable behavior, clear limits, evidence, and recovery—not from confident tone or decorative trust badges.

### Requirements

- Show source, freshness, assumptions, and scope when they affect a decision.
- Keep durable activity and change history for important workflows.
- Make system limitations and unavailable data visible at the point of use.
- Separate model suggestions from authoritative records.
- Enforce permissions and action boundaries outside the presentation layer.

### Failure modes

- Confidence scores without explanation or calibration.
- Citations that do not support the claim.
- Hidden automatic changes.
- Interfaces implying that an AI recommendation is verified fact.

### Audit and evidence

Trace a consequential output back to inputs, changes, and decisions. Ask whether a skeptical user can inspect enough to approve, correct, or reject it.

## 15. Design the whole lifecycle

### Intent

Product quality includes first use, repeated use, collaboration, interruption, change, failure, and return—not only a successful demo.

### Requirements

- Design entry, onboarding, normal use, advanced use, interruption, recovery, completion, and return.
- Handle empty, sparse, dense, stale, partial, failed, archived, and permission-limited data.
- Support collaboration, ownership, handoff, notification, and history where the work spans people.
- Preserve continuity across navigation, refresh, reconnect, and device changes where appropriate.

### Failure modes

- Beautiful populated screens with useless empty states.
- Tasks that disappear when a tab closes.
- Notifications that link to missing context.
- No experience for a returning user with unfinished work.

### Audit and evidence

Build a state matrix for every critical workflow and test transitions, not only screenshots. Include asynchronous completion and concurrent change.

## 16. Measure whether the experience improved

### Intent

Implementation completion is not proof of product improvement.

### Requirements

- Define the user outcome and baseline before redesign.
- Select measures appropriate to the workflow: completion, time, error, correction, abandonment, support demand, adoption, retention, override, comprehension, or satisfaction.
- Pair quantitative signals with direct observation and user feedback.
- Instrument only what will inform a product decision.

### Failure modes

- Success defined as shipping or page views.
- Optimizing clicks when fewer clicks do not mean less effort.
- Treating AI acceptance as quality without measuring correction or false acceptance.
- Collecting analytics without owners or decision thresholds.

### Audit and evidence

State what result would confirm, challenge, or reverse the change. Compare the improved workflow with the baseline under realistic conditions.

## Principle conflicts and tradeoffs

Principles can compete. Dense information may improve expert efficiency but burden new users. Confirmation can prevent harm but create fatigue. Consistency can conflict with a domain-specific need. Personalization can reduce repetition but weaken predictability. Resolve these conflicts through the user, task, frequency, consequence, and evidence—not by declaring one principle absolute.

Document the tradeoff in the implementation specification and validate the riskier assumption with the intended users.
