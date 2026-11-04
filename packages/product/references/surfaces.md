# Surfaces

Use this list so a broad audit does not collapse into a review of the signed-in dashboard. It records what applies; no app needs every surface.

## Surface families

| Family | Look for |
|---|---|
| Public marketing and trust | Home, pricing, lead forms, legal, security, status, sign-in entry |
| Acquisition and identity | Registration, invitation, sign-in, SSO, recovery, trial, onboarding, activation |
| Core customer application | Dashboard, domain objects, create and edit, search, bulk actions, import and export, collaboration, reporting |
| Customer administration | Organisation settings, members, roles, integrations, audit history, usage limits |
| Internal operations | Staff console, impersonation, case queues, moderation, exception handling, escalation |
| Billing and commerce | Upgrade, checkout, invoices, metering, renewal, cancellation, failed payment, refund |
| Account and security | Profile, sessions, MFA, API keys, connected accounts, export, deletion |
| Developer and integration | API docs, credentials, webhooks, event logs, scopes, test mode, rate limits |
| Help and service | In-product help, support contact, feedback, ticket status, release notes |
| Lifecycle communications | Transactional email, alerts, deep links, unsubscribe, expired links |
| System and recovery | Empty, loading, partial, stale, offline, maintenance, 401, 403, 404, 409, 429, 500, timeout, undo, restore |
| Platform and delivery | Mobile web, native apps, extensions, embeds, exports, shared links, localisation, theming |

## Roles

Cover each role that applies:

- Anonymous visitor
- Invited or registering user
- Standard member
- Manager or approver
- Organisation and billing owner
- Customer administrator
- Read-only, suspended or expired user
- External guest
- Internal support, operations and platform staff
- Cross-organisation and delegated access

Keep customer administration and internal staff tools separate, because they have different users, permissions and consequences.

## Check each surface for

Purpose, entry and return, labels and navigation, states, permissions, accessibility, responsive behaviour, trust and reversibility, perceived speed, measurement.

## Coverage table

Use one row per surface or route group:

| Surface | Route | Role | Critical journey | Status | Evidence | States checked | Findings |
|---|---|---|---|---|---|---|---|

An audit is broad only when every family has an applicability decision and every discovered surface has a status.
