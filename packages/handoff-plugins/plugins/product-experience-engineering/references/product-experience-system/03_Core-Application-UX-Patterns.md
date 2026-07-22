# Core Application UX Patterns

## Purpose

Agentic features cannot rescue a weak application foundation. This library covers the persistent structures and recurring workflows that make operational software useful: navigation, search, queues, tables, forms, details, documents, notifications, settings, responsiveness, and state behavior.

Apply patterns according to the user’s task and information—not because a component already exists.

## 1. Application shell and global navigation

### User need

Users need a stable sense of location, access to major product areas, and uninterrupted space for the current task.

### Anatomy

- Product/workspace identity and account context.
- Primary navigation organized by user-recognizable areas or objects.
- Current-area and current-page indication.
- Global search or command access when justified.
- Task/notification/user utilities that do not compete with primary navigation.
- Main-content landmark, page title, and contextual actions.

### Behavior

Navigation reflects the product’s information architecture, not the internal service architecture. Use nouns for destinations and verbs for actions. Keep the highest-frequency areas directly accessible; place infrequent administration separately. Preserve location and unsaved-work behavior across responsive transitions.

On narrow screens, collapse navigation into an explicit menu or compact rail while retaining the page title, primary action, and critical status. Never rely on hover-only submenus.

### Failure modes

- Every feature presented as an equal top-level item.
- Workspace/account switching hidden inside an unrelated user menu.
- Navigation labels that change by route.
- A wide permanent sidebar that leaves the work surface unusable on smaller laptops.

## 2. Page headers, breadcrumbs, and local navigation

Every page should identify its object or task. A useful header can include title, status, owner, key metadata, primary action, and a restrained set of secondary actions.

Use breadcrumbs when hierarchy helps users understand and move among parents. Do not use them as a substitute for a clear page title or browser history. Use tabs when sibling views represent stable facets of the same object; keep tab state linkable and do not hide critical errors on an inactive tab without a visible indicator.

For deep areas, local side navigation can expose related destinations more effectively than large dropdowns. Keep page-level actions out of navigation.

## 3. Search and command surfaces

### Search

Search supports users who know or can describe what they need. Define searchable objects, fields, freshness, permission behavior, and result ranking. Show query, result count or boundedness, active scope, applied filters, and why a result is relevant where feasible.

Provide useful zero-result behavior: correct likely mistakes, relax filters, suggest alternate terms, or offer creation only when appropriate. Preserve the query and result context when users open an item and return.

### Command surfaces

A command palette accelerates known actions for frequent users; it does not replace discoverable navigation. Group navigation, object actions, and recent items. Include keyboard access, text labels, shortcuts, permission-aware availability, and predictable focus/escape behavior.

### Agent-assisted search

Natural-language search may translate intent into visible structured filters or synthesize results with evidence. Show the interpreted scope and let users correct it. Keep direct result access and deterministic filtering available.

## 4. Dashboards and home surfaces

### Purpose

A dashboard should support orientation and action, not prove that data exists.

### Content priority

1. Work requiring the user’s attention.
2. Recent or resumable work.
3. Changes, exceptions, deadlines, and risks.
4. Key trends that support a decision.
5. Discovery or guidance appropriate to the user’s maturity.

Every metric needs a label, time range, definition, comparison context, freshness, and a route to the underlying items. Avoid ambiguous color-only trends and decorative charts. Let role and product context shape the dashboard rather than creating one generic executive view for everyone.

Empty dashboards should help users create/import/connect their first meaningful object. Returning-user dashboards should not reset into onboarding.

## 5. Work queues and task lists

Operational users often need to decide what to handle next. A work queue should make prioritization legible through status, urgency, age, owner, key exception, and next action.

Support predictable sorting, filtering, assignment, saved views, bulk operations, and return context. Separate system priority from user-controlled ordering. If an agent recommends priority, show the factors and let users override it.

Queues need states for no work, no results under current filters, loading, stale results, partial data, permission-limited items, and failed refresh. Do not use the same empty message for all of them.

## 6. Data tables

### When to use

Use a table when users compare the same attributes across many items, scan exceptions, or operate on rows. Use cards or lists when content varies substantially or the primary need is sequential reading.

### Anatomy

- Descriptive caption or nearby heading.
- Stable row identity and primary link.
- Columns selected for the decision, not every available field.
- Sort state, filters, result count, selection count, pagination or virtualization behavior.
- Row and bulk actions.
- Loading, empty, error, and partial states.

### Behavior

Keep the primary identifier and critical status visible. Align numeric data, use explicit units, format dates with timezone context when material, and retain raw sortable values. Make columns configurable when user roles genuinely differ; provide a sensible default and reset.

Selection must survive only when the user can understand its scope. State whether “select all” means the page, loaded results, or the entire filtered set. Before bulk changes, summarize affected count, exclusions, and consequences.

For narrow screens, choose deliberately: horizontal scrolling with sticky identity/actions, a stacked detail pattern, column prioritization, or a separate mobile list. Do not compress a complex table until text and targets become unusable.

### Accessibility

Use semantic table structure, header associations, accessible sort buttons, an announcement of sort results, visible keyboard focus, and non-hover access to row actions. Test sticky, virtualized, and scrollable implementations with keyboard and screen readers.

## 7. Filters, sorting, saved views, and pagination

### Filters

Show active filters as removable values and make the total effect visible. Distinguish default scope from user-applied filters. Preserve filters when users inspect an item and return. Offer “clear all” without erasing unrelated view preferences.

Use immediate application for lightweight, reversible filtering and an Apply action when several choices form one query or the operation is expensive. Indicate pending changes in the latter case.

### Sorting

Provide a meaningful default and visible direction. Avoid sorting columns whose displayed values do not match sort semantics. Explain ranked or AI-relevance order when it changes user decisions.

### Saved views

Saved views capture a useful configuration: filters, sort, columns, grouping, and sometimes density. Name personal versus shared views, show ownership and last update, and handle deleted fields gracefully.

### Pagination and infinite loading

Use pagination when users need bounded location, return context, or direct movement among result pages. Use incremental loading for exploratory feeds where position is less important. Always preserve a route back to the same place and provide result-set size or boundedness.

## 8. Object detail and workspace pages

### Purpose

An object page should answer: what is this, what is its state, what matters now, what happened, and what can I do?

### Composition

- Identity, status, ownership, and high-value metadata.
- Primary workflow actions.
- Summary of exceptions or required attention.
- Main working content.
- Related records, documents, communications, and activity.
- Agent support embedded near the relevant context.

Use progressive disclosure and stable sections or tabs. Do not spread one decision across several tabs without a summary. Keep action results reflected in the canonical object state, not only a toast or chat message.

## 9. Forms and data entry

### Question design

Ask only for information needed now. Use labels that remain visible, concise hints for format or purpose, and examples when ambiguity is likely. Group fields by the user’s mental model. Use appropriate controls: radio buttons for a small exclusive set, checkboxes for independent choices, search/select for large known sets, and free text only when structured choices cannot represent the answer.

### Defaults and derived values

Prefill safe known data and disclose consequential assumptions. Make derived fields inspectable and editable when the user may know better. Do not use placeholder text as a label.

### Validation

Validate on submission by default; add earlier validation only when it prevents meaningful wasted effort. Preserve entered values. Put a specific message beside each field and, for long forms, provide a linked summary and focus it after submission. Separate validation errors from service failures and permission failures.

### Saving

Choose one visible model: explicit save, autosave, draft plus publish, or staged review. If autosaving, show saving/saved/error state and protect against concurrent overwrite. For long work, preserve drafts and explain retention.

## 10. Multi-step and branching workflows

Use a multi-step flow when sequence reduces complexity or later questions depend on earlier answers. Show progress using meaningful step names. Let users return without losing valid answers, and explain when changing an earlier answer invalidates later work.

Before consequential submission, provide a review surface with editable sections. After submission, show outcome, reference, what happens next, expected timing, and available correction. Avoid step counts that change unpredictably without explanation.

## 11. Documents, uploads, and generated artifacts

### Upload

State accepted types, limits, privacy/context, and what happens after upload. Validate early, preserve successful files when another fails, show per-file progress, allow removal/cancel, and explain processing states separately from transfer.

### Document workspace

Support preview, metadata, version, source, status, ownership, related object, extraction results, comments, and activity according to the product. Preserve the original and distinguish extracted or generated content. Provide zoom, download, accessible text where available, and a usable narrow-screen alternative.

### Generated artifacts

Treat reports, letters, summaries, or plans as versioned drafts. Show source and generation time, allow structured edits, record approval/finalization, and prevent regeneration from silently replacing human changes.

## 12. Notifications, inboxes, and attention management

Notifications should communicate a meaningful change or required action. Include object, outcome, urgency, and direct context. Group repeated events and avoid duplicating the same interruption across channels without purpose.

An in-product inbox needs read/unread state only if it helps; task state is usually more important. Provide preference by event category and urgency, not by internal service. Critical alerts must be actionable and rare enough to retain meaning.

## 13. Activity history and collaboration

Activity history records significant changes, decisions, communications, approvals, and agent actions. Show actor, action, object, time, and outcome. Group noisy mechanical events and expand details on demand.

Comments and mentions need durable context, permission-aware recipients, resolution state when used for review, and links to the exact object or selection. For handoffs, show owner, next action, due context, and unresolved blockers.

## 14. Settings, permissions, and integrations

Organize settings by user-recognizable concern: profile, workspace, team, notifications, integrations, data, appearance, and product-specific configuration. Show scope—personal, team, workspace, or system—and save behavior.

Permissions need an understandable role/capability model. Hide or disable unavailable actions according to whether awareness helps; when disabled, explain how access can be obtained. Integration screens should show connection identity, granted scope, health, last synchronization, errors, and disconnect consequences.

## 15. Empty, loading, error, and recovery states

Every important surface must distinguish:

| State | Required answer |
| --- | --- |
| First-use empty | What belongs here, why it matters, and how to create/connect the first item. |
| User-created empty | What the user removed/completed and the next useful action, if any. |
| Filtered empty | Which filters caused no results and how to change them. |
| Loading | What region is loading; preserve useful prior content when safe. |
| Stale | When data was last current and how refresh affects work. |
| Partial | What loaded or succeeded, what did not, and whether retry is scoped. |
| Validation error | What input is unusable and how to correct it without losing work. |
| Expected service error | What failed, whether data changed, and the safest next action. |
| Unexpected failure | A stable fallback, reference for diagnosis, and retry/navigation options. |
| Permission denied | What is unavailable, why at an appropriate level, and who can help. |
| Offline/reconnecting | What remains available, what is queued, and synchronization status. |
| Success | The result, affected object, next step, and reversal where applicable. |

## 16. Responsive and keyboard behavior

Responsive design preserves task priority, not the desktop arrangement. For each workflow define:

- which context remains visible;
- where navigation moves;
- how tables and comparison change;
- where primary and bulk actions live;
- how drawers, dialogs, and inspectors occupy the viewport;
- how touch targets, virtual keyboards, and safe areas affect forms;
- what can be deferred without blocking the task.

Keyboard behavior needs logical tab order, visible focus, skip links/landmarks, established composite-widget patterns, escape behavior, and shortcuts that do not override typing or assistive technology. Shortcuts supplement visible controls.

## Pattern validation checklist

For every implemented core pattern, verify:

1. Clear user task and page purpose.
2. Complete state matrix, including partial and recovery behavior.
3. Stable navigation and return context.
4. Narrow and wide viewport behavior.
5. Keyboard and accessible name/focus/status behavior.
6. Realistic sparse and dense data.
7. Permission, stale data, and concurrent-change behavior.
8. Copy that predicts actions and supports correction.
9. Performance and perceived-continuity behavior.
10. Integration with agent activity without duplicating the canonical product state.
