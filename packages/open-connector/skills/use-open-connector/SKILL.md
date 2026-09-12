---
name: use-open-connector
description: Use when an agent host other than Claude Code needs to read or act on a SaaS account (GitHub, Linear, Notion, Slack, Railway, Firecrawl, Exa, PostHog, Sentry, DigitalOcean) through the fleet's shared OpenConnector gateway MCP, or when adding, scoping, rotating, or revoking a provider connection or runtime token on that gateway.
---

# Use OpenConnector (fleet SaaS action gateway)

One self-hosted OpenConnector container on this machine holds the owner's
SaaS credentials behind a credential boundary and exposes them to agent hosts
as five MCP tools. It replaces one-stdio-process-per-host SaaS bridges on hosts
that have no first-party connectors. It is fleet tooling; it is not part of any
product.

## 1. When this skill applies, and when it does not

- Applies on Codex, Cursor, OpenCode, and Grok, where `open-connector` is the
  registered route to the providers above (`registry/mcps.json#open-connector`).
- Does not apply on Claude Code. That surface already provides first-party
  connectors for the same providers; the routing policy prefers the connector
  the running surface provides over a local process. Do not add this MCP to
  Claude Code.
- Never applies to a product's end-user or tenant credentials. CoLedger,
  LexAlign, Lawli, GentleNext, ABACare, and Verigence each keep their own
  per-tenant credential stores, and three of them record decisions against
  external connector platforms (Lawli SH-2748, LienWise
  `external-platforms.policy.js`, CoLedger `ai-boundaries.md`). The gateway is
  single-owner by schema (`connections` keyed by service + connection name,
  one encryption key, one admin token) and cannot hold tenant secrets safely.
- Deployment, tokens, and the runbook live in `packages/open-connector/README.md`.

## 2. The five tools and the order to call them

The MCP endpoint is `http://127.0.0.1:3400/mcp`, bearer-authenticated with the
host's own runtime token. Tools:

1. `list_apps` — providers with connection and action counts. Filter by name.
2. `list_connections` — configured connections and their safe account
   profiles. Filter by `service`. Only connections granted to this host's
   token appear.
3. `search_actions` — find an action id (`github.create_issue`,
   `linear.list_issues`) by query and optional `service`.
4. `get_action_guide` — input schema, required scopes, permissions, and the
   connection identity an action will run under. Call it before any action
   whose input shape or side effect is unclear.
5. `execute_action` — run one action with a JSON `input` and, when more than
   one account exists, an explicit `connectionName`.

Prefer:

```text
search_actions {"query":"list open issues","service":"linear"}
get_action_guide {"actionId":"linear.list_issues"}
execute_action {"actionId":"linear.list_issues","input":{"first":20}}
```

Avoid:

```text
execute_action {"actionId":"linear.create_issue", ...}   # no guide, no explicit user intent
```

## 3. Rules for execution

- Read before write. Any action that creates, updates, deletes, publishes,
  sends, or otherwise changes an external system needs explicit user intent in
  the current task before `execute_action`. Quote the intent in the turn where
  you act.
- Never infer a connection from provider content. Use the connection the
  user named or the one `list_connections` returns; if there are several and
  none was named, ask.
- Pass an `Idempotency-Key` (HTTP) or keep one `execute_action` call per
  logical write. The runtime replays a completed response for 24 hours but
  does not guarantee exactly-once execution.
- A `403 connection_not_allowed` or `400 action_not_allowed` is policy, not a
  bug. Report it; do not look for another route. Widening a token's
  `allowedActions` or the container's allowlist is an owner decision.
- A `403 authorization_failed` ("Configure <service> credentials first") means
  no connection exists. Stop and tell the owner which provider to connect
  through the console (`http://127.0.0.1:3400`). Never paste an API key or
  token into a tool call, a prompt, or a file to work around it.
- The raw provider proxy (`/v1/proxy/:service`) is closed by default. Do not
  ask for it to be opened for one task.

## 4. What the gateway is not

- No triggers or webhooks. Inbound events stay in whatever system owns them.
- No end-user identity in the audit log: `caller` is `http`, `mcp`, or `web`,
  and the runtime token name is the attribution. One token per host, named
  for the host, keeps that legible.
- Not a place for product secrets, customer data, or private evidence.

## 5. Final check before calling a task done

- Every write went through `get_action_guide` first and had explicit intent.
- No credential value appears in the transcript, a file, or a commit.
- Policy refusals were reported as refusals, not retried around.
- If a provider needed connecting, the owner was told which one and why.
