---
name: use-open-connector
description: Use when an agent host other than Claude Code needs to read or act on Brave Search, a no-auth research/dev source (npm, Hacker News, arXiv, PubMed, and similar), or a long-tail api_key provider (PostHog, Sentry, DigitalOcean) through the fleet's shared OpenConnector gateway MCP, or when adding, scoping, rotating, or revoking a provider connection or runtime token on that gateway.
---

# Use OpenConnector (fleet SaaS action gateway)

One self-hosted OpenConnector container on this machine holds the owner's
SaaS credentials behind a credential boundary and exposes them to agent hosts
as five MCP tools. It is fleet tooling; it is not part of any product.

## 1. When this skill applies, and when it does not

- Applies on Codex, Cursor, OpenCode, and Grok, where `open-connector` is the
  registered route to Brave Search, the no-auth research/dev sources, and the
  long-tail api_key providers below (`registry/mcps.json#open-connector`).
- Does not apply on Claude Code. That surface already provides first-party
  connectors for the providers it covers; the routing policy prefers the
  connector the running surface provides over a local process. Do not add
  this MCP to Claude Code.
- Does not apply to GitHub, Linear, Notion, Context7, Exa, Firecrawl,
  Railway, or Descript. Those stay on their official hosted MCPs, already
  deployed fleet-wide with zero local processes, and are deliberately absent
  from this gateway's allowlist. Do not widen the allowlist to add one back;
  route to the hosted MCP instead.
- Does not apply to Slack. Slack read/write authority is AgentHub-owned
  (`packages/slack`), not this gateway.
- Never applies to a product's end-user or tenant credentials. CoLedger,
  LexAlign, Lawli, GentleNext, ABACare, and Verigence each keep their own
  per-tenant credential stores, and three of them record decisions against
  external connector platforms (Lawli SH-2748, LienWise
  `external-platforms.policy.js`, CoLedger `ai-boundaries.md`). The gateway is
  single-owner by schema (`connections` keyed by service + connection name,
  one encryption key, one admin token) and cannot hold tenant secrets safely.
- Deployment, tokens, and the runbook live in `packages/open-connector/README.md`.

## 2. Token model

Two runtime tokens exist and are deliberately named differently:

- `OPEN_CONNECTOR_RUNTIME_TOKEN` is the bootstrap token in the runtime `.env`.
  It is for the operator wrapper and the compose healthcheck only. Never put
  it in a host config or a host's environment.
- `OPEN_CONNECTOR_AGENT_TOKEN` is a minted, revocable, per-host runtime token
  stored in the Windows **User**-scope environment, the same way the fleet
  already keeps `CONTEXT7_API_KEY`, `FIRECRAWL_API_KEY`, `EXA_API_KEY`, and
  `BRAVE_API_KEY`. This is what a host's MCP config should reference by name.
  Mint one with `Invoke-OpenConnector.ps1 mint-token -Name <host> -AllowedActions
  <list> -StoreUserEnv OPEN_CONNECTOR_AGENT_TOKEN`, then restart the host
  process so it picks up the new environment variable.

## 3. The five tools and the order to call them

The MCP endpoint is `http://127.0.0.1:3400/mcp`, bearer-authenticated with the
host's own `OPEN_CONNECTOR_AGENT_TOKEN`. Tools:

1. `list_apps` — providers with connection and action counts. Filter by name.
2. `list_connections` — configured connections and their safe account
   profiles. Filter by `service`. Only connections granted to this host's
   token appear.
3. `search_actions` — find an action id (`npm.get_package`,
   `brave_search.web_search`) by query and optional `service`.
4. `get_action_guide` — input schema, required scopes, permissions, and the
   connection identity an action will run under. Call it before any action
   whose input shape or side effect is unclear.
5. `execute_action` — run one action with a JSON `input` and, when more than
   one account exists, an explicit `connectionName`.

Prefer:

```text
search_actions {"query":"web search","service":"brave_search"}
get_action_guide {"actionId":"brave_search.web_search"}
execute_action {"actionId":"brave_search.web_search","input":{"query":"..."}}
```

Avoid:

```text
execute_action {"actionId":"sentry.update_issue", ...}   # no guide, no explicit user intent
```

## 4. Rules for execution

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
  through `Invoke-OpenConnector.ps1 connect` or the console
  (`http://127.0.0.1:3400`). Never paste an API key or token into a tool
  call, a prompt, or a file to work around it.
- The raw provider proxy (`/v1/proxy/:service`) is closed by default. Do not
  ask for it to be opened for one task.
- A no-auth provider (npm, Hacker News, arXiv, and the rest of the no-auth
  list) is always connected -- there is nothing to configure and no
  `authorization_failed` to expect for one of these.

## 5. What the gateway is not

- No triggers or webhooks. Inbound events stay in whatever system owns them.
- No end-user identity in the audit log: `caller` is `http`, `mcp`, or `web`,
  and the runtime token name is the attribution. One token per host, named
  for the host, keeps that legible.
- Not a place for product secrets, customer data, or private evidence.
- Not a route to GitHub, Linear, Notion, Context7, Exa, Firecrawl, Railway,
  Descript, or Slack -- see §1.

## 6. Final check before calling a task done

- Every write went through `get_action_guide` first and had explicit intent.
- No credential value appears in the transcript, a file, or a commit.
- Policy refusals were reported as refusals, not retried around.
- If a provider needed connecting, the owner was told which one and why.
