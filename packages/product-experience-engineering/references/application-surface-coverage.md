# Application Surface Coverage

Use this model to prevent a broad audit from quietly collapsing into a review of the authenticated dashboard. It is an applicability inventory, not a demand that every application implement every surface.

## Surface families

| Surface family | Typical areas to discover |
|---|---|
| Public marketing and trust | Home, landing pages, solutions, features, pricing, comparison, about, contact, demos, lead forms, content, search, legal, privacy, security, trust center, status, sign-in entry points |
| Acquisition and identity | Registration, invitation, sign-in, SSO, verification, passwordless or password recovery, consent, trial, plan selection, first-run setup, onboarding, activation, abandoned-flow return |
| Core customer application | Home/dashboard, workspaces, domain objects, creation and editing, search, filter, sort, bulk actions, import/export, collaboration, comments, history, notifications, reporting, decision and completion flows |
| Customer administration | Organization settings, members, teams, roles, permissions, policies, integrations, audit history, retention, branding, environments, usage limits, data administration |
| Internal operations | Staff console, support impersonation, case queues, review/moderation, fulfillment, exception handling, customer operations, content management, finance operations, audit and escalation tools |
| Billing and commerce | Trial, upgrade, downgrade, checkout, invoices, payment methods, taxes, coupons, metering, usage, renewal, cancellation, failed payment, refund, entitlement changes |
| Account and security | Profile, preferences, accessibility, notification settings, sessions, devices, MFA, recovery codes, API keys, connected accounts, export, deletion, suspension |
| Developer and integration platform | API documentation, credentials, webhooks, event logs, integration catalog, connection setup, scopes, test mode, samples, rate limits, failure recovery |
| Help and service | In-product help, documentation, tours, support contact, feedback, issue reporting, chat, ticket status, announcements, release notes, service status |
| Lifecycle communications | Transactional email, invitations, alerts, digests, SMS/push where applicable, deep links, unsubscribe/preferences, expired links, cross-channel continuity |
| System and recovery | Empty, loading, partial, stale, offline, degraded, maintenance, 401, 403, 404, 409, 429, 500, timeout, retry, undo, destructive confirmation, restore, data loss prevention |
| Platform and delivery | Responsive web, mobile web, PWA, native apps, browser extensions, embedded widgets, printable/exported documents, public/shared links, localization, theming |

## Role and tenancy coverage

Inventory surfaces for each applicable access context:

- Anonymous visitor and prospect
- Invited or registering user
- Standard authenticated member
- Manager, reviewer, or approver
- Organization owner and billing owner
- Customer administrator
- Read-only, suspended, expired, or restricted user
- External collaborator, client, vendor, or guest
- Internal support, operations, finance, content, and platform administrator
- Single-tenant, multi-tenant, cross-organization, and delegated-access contexts

Do not merge customer administration with internal staff tooling. They serve different users, consequences, permissions, and workflows.

## Cross-cutting review dimensions

For every applicable surface, record:

| Dimension | Questions |
|---|---|
| Purpose and utility | What user outcome does this surface enable? Is it complete and worth having? |
| Entry and continuity | How do users arrive, resume, leave, and return across routes and channels? |
| Information architecture | Are objects, labels, navigation, hierarchy, search, and relationships understandable? |
| Interaction states | Are normal, empty, loading, partial, error, success, permission, and recovery states complete? |
| Roles and permissions | Is access understandable, least-surprising, and recoverable without leaking information? |
| Accessibility | Can users perceive, understand, navigate, and operate it with keyboard, zoom, reflow, and assistive technology? |
| Responsive behavior | Does priority and interaction adapt across supported widths and input modes? |
| Trust and safety | Are consequences, data use, external actions, destructive actions, and reversibility clear? |
| Performance perception | Is progress visible and does the interface preserve context during latency? |
| Measurement | Can task success, failure, recovery, and abandonment be evaluated without collecting unnecessary private content? |

## Coverage ledger

Use one row per surface or coherent route group:

| Surface | Route/channel | Audience/role | Critical journey | Status | Evidence | States checked | Findings/unknowns |
|---|---|---|---|---|---|---|---|

Allowed status values:

- `Not applicable`: evidence supports exclusion.
- `Discovered`: existence and purpose identified.
- `Shallow reviewed`: structure and obvious states inspected.
- `Deep reviewed`: critical journeys and applicable dimensions exercised.
- `Blocked`: access, environment, data, or role is unavailable.

A broad audit is complete only when every surface family has an applicability decision and every discovered surface has a coverage status. Deep review remains risk-prioritized; do not claim exhaustive testing when coverage is shallow or blocked.

