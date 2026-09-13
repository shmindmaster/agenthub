# open-connector

Fleet SaaS action gateway: one self-hosted
[oomol-lab/open-connector](https://github.com/oomol-lab/open-connector)
container on this machine, exposed to non-Claude agent hosts as a five-tool
MCP. Pilot, registered 2026-09-12. Assessment that led here:
[OpenConnector Fit Assessment](https://claude.ai/code/artifact/1c336229-6774-4e2b-9a20-139111ae1d22).

## What it is for

- Brave Search (replacing the retired `brave-search` npx stdio bridge), a set
  of no-auth research/dev sources (npm, Hacker News, arXiv, Crossref,
  DataCite, PubMed, Europe PMC, bioRxiv/medRxiv, ClinicalTrials.gov, openFDA,
  WHO GHO, QuickChart, wttr.in, OSS Insight, AppleDB), and long-tail api_key
  providers the owner chooses to connect that have no hosted MCP in the fleet
  (PostHog, Sentry, DigitalOcean).
- Codex, Cursor, OpenCode, and Grok reach those providers through one shared
  local HTTP process instead of one stdio bridge per host per provider.
- Claude Code keeps its first-party connectors; this MCP is not added there.
- Owner-only credentials. Not a product component, not a tenant credential
  store. See `skills/use-open-connector/SKILL.md` §1 for the boundary and the
  product decisions that fix it.

## What it is NOT for

- GitHub, Linear, Notion, Context7, Exa, Firecrawl, Railway, and Descript.
  Those stay on their official hosted MCPs, already deployed fleet-wide with
  zero local processes -- this gateway does not duplicate them, and they are
  not in the allowlist.
- Slack. Slack read/write authority is AgentHub-owned (`packages/slack`), not
  this gateway.
- Any credential a hosted MCP already covers. Route through the hosted MCP
  first; add a provider here only when no hosted MCP exists.

## Token model

Two runtime tokens exist, for different consumers, and they are deliberately
named differently so one can never shadow the other:

| Token | Env var | Who uses it | Scope |
| --- | --- | --- | --- |
| Bootstrap | `OPEN_CONNECTOR_RUNTIME_TOKEN` (runtime `.env`, passed to the container as `OOMOL_CONNECT_RUNTIME_TOKEN`) | The operator wrapper (`Invoke-OpenConnector.ps1`) and the compose healthcheck only | Full -- never hand it to an agent host |
| Agent | `OPEN_CONNECTOR_AGENT_TOKEN` (Windows **User**-scope environment variable, the way the fleet already keeps `CONTEXT7_API_KEY`, `FIRECRAWL_API_KEY`, `EXA_API_KEY`, `BRAVE_API_KEY`) | Non-Claude agent hosts, via `mint-token -StoreUserEnv OPEN_CONNECTOR_AGENT_TOKEN` | Scoped to the action allowlist given at mint time, revocable independently of the bootstrap token |

Never put the bootstrap token in a host config or a host's environment. A
host config that reads `OPEN_CONNECTOR_RUNTIME_TOKEN` by name is wrong; it
should read `OPEN_CONNECTOR_AGENT_TOKEN`.

## Layout

| Path | Role |
| --- | --- |
| `docker-compose.yml` | Pinned image (v1.5.0 by digest), loopback bind, policy env |
| `.env.example` | Variable names for the runtime env file (no values) |
| `scripts/Invoke-OpenConnector.ps1` | `start` / `stop` / `status` / `probe` / `connect` / `disconnect` / `list-connections` / `mint-token` / `list-tokens` / `revoke-token` / `smoke` / `exit-test` |
| `skills/use-open-connector/SKILL.md` | Agent-facing usage and rules |

Runtime state lives under `%LOCALAPPDATA%\AgentHub\runtime\open-connector\`:
`.env` (secrets) and `data\` (SQLite database, transit files). Neither is in
any repository.

## Runbook

1. Copy `.env.example` to `%LOCALAPPDATA%\AgentHub\runtime\open-connector\.env`
   and set `OPEN_CONNECTOR_DATA_DIR`, `OPEN_CONNECTOR_ENCRYPTION_KEY`,
   `OPEN_CONNECTOR_ADMIN_TOKEN`, `OPEN_CONNECTOR_RUNTIME_TOKEN`
   (`python -c "import secrets; print(secrets.token_urlsafe(48))"`). The
   encryption key is not recoverable if lost.
2. `pwsh -NoProfile -File packages/open-connector/scripts/Invoke-OpenConnector.ps1 start`
   then `status` and `probe`. `probe` prints the MCP protocol revision and the
   tool list, and confirms an unauthenticated call is refused.
3. Connect a provider:
   - No-auth providers (npm, Hacker News, arXiv, ...) are already connected --
     the runtime treats them as always-available virtual connections. `connect
     -Service npm` is a harmless idempotent confirmation, not a creation step.
   - An api_key provider (Brave Search, PostHog, Sentry, DigitalOcean) needs
     its key in a local environment variable first, then
     `connect -Service brave_search -ApiKeyEnv BRAVE_SEARCH_API_KEY`. The
     wrapper reads the named variable and puts the value straight into the
     request body; it is never printed or logged.
   - `list-connections` shows what is configured, with no credential material.
   - `disconnect -Service <id>` removes a real connection. It is a no-op on a
     virtual no-auth connection, which cannot be removed.
4. Mint one persistent, scoped runtime token per host and store it directly in
   that host's User-scope environment, without ever printing it:
   ```
   Invoke-OpenConnector.ps1 mint-token -Name codex -AllowedActions 'brave_search.*','npm.*' -StoreUserEnv OPEN_CONNECTOR_AGENT_TOKEN
   ```
   Restart the host process (or its terminal) so it picks up the new User
   environment variable -- a process only reads its environment at launch.
   `list-tokens` and `revoke-token -Id <id>` manage tokens afterward; rotate by
   minting a new one and revoking the old one.
5. `smoke -Action <provider.action>` proves an action end to end through MCP
   `execute_action` once a connection exists and the container's allowlist
   covers it. Use `get_action_guide` via `probe`/manual MCP calls, or the
   skill's tool order below, when a dry check is enough.
6. `exit-test` proves revocation and the no-auth connect/disconnect round trip
   work before the gateway holds anything real for a new host.
7. Deployment to a host config is a separate, reviewed step: add
   `open-connector` to `registry/native-connectors.json →
   lifecyclePolicy.persistedOnDemandLocalMcpIds`, record the host's exposure,
   and run `scripts/Sync-AgentHub.ps1 -Apply -Validate` from the main
   checkout. That persistence flip is the orchestrator's job, not this
   package's -- until it happens, the registry entry is eligibility, not
   deployment.

## The five MCP tools, in order

1. `list_apps` -- providers with connection and action counts.
2. `list_connections` -- configured connections, filterable by `service`.
3. `search_actions` -- find an action id by query and optional `service`.
4. `get_action_guide` -- input schema, required scopes, and the connection an
   action will run under. Call before any action whose shape is unclear.
5. `execute_action` -- run one action with a JSON `input`.

Full rules for calling them are in `skills/use-open-connector/SKILL.md`.

## Policy defaults (compose)

- Bound to `127.0.0.1:3400`. Port 3000 is Duckie; 7337/7338 are RepoWise.
- `OOMOL_CONNECT_ALLOWED_ACTIONS` is an explicit provider allowlist; widen per
  provider, never to `*`. Current default: `brave_search.*`, the no-auth
  research/dev sources listed under "What it is for", and `posthog.*` /
  `sentry.*` / `digital_ocean.*`. GitHub, Linear, Notion, Slack, Railway,
  Firecrawl, Exa, Descript, and Context7 are deliberately absent -- see "What
  it is NOT for".
- `OOMOL_CONNECT_BLOCKED_PROXIES=*`: the raw provider proxy is closed.
- `OOMOL_CONNECT_ALLOW_PRIVATE_NETWORK=false`: provider executors cannot reach
  loopback, link-local, metadata, or RFC 1918 targets.
- `/v1/health` and `/mcp` require the runtime bearer; `/api/*` and the console
  require the admin token. Both verified 2026-09-12.

## Verified 2026-09-12 (image v1.5.0, digest `b9e6133c…`)

- `initialize` returns `protocolVersion 2025-11-25`; `server/discover` is
  `-32601 Method not found`; five tools listed.
- Unauthenticated `/mcp` and `/v1/health` return 401.
- `stripe.list_customers` (outside the allowlist) returns
  `400 action_not_allowed` with `auditPersisted: true`.
- Runtime token create → accept → revoke → refuse passes (`exit-test`).
- 1,465 providers served by the image (main at `33dd4ad` carries 1,498).

## Verified 2026-09-13 (live container, connect/disconnect and route shapes)

- `GET /openapi.json` (admin token) is the authoritative route source; the
  cloned `main` source tree is newer than the deployed image and mounts
  connection routes differently (`/v1/...` there vs. `/api/connections/...`
  live) -- always confirm against the running container's own OpenAPI
  document before relying on a route.
- `PUT /api/connections/{service}` body is `{authType, connectionName?,
  values?}` (`authType` one of `no_auth`, `api_key`, `custom_credential`).
  `DELETE /api/connections/{service}?connectionName=<name>` disconnects.
- A no-auth provider (npm, Hacker News, ...) is already `configured: true,
  virtual: true` in `GET /api/connections` before any connect call --
  `connect` on one is an idempotent confirmation, and `disconnect` on one is a
  verified no-op (still returns `configured: true`, since it cannot be
  removed).
- `GET /api/connections` does not honor a `?service=` filter (unlike the MCP
  `list_connections` tool); the wrapper filters client-side.
- `npm.*` and the other providers added in this pass are not yet in the
  container's live allowlist -- it still runs the previous default until the
  orchestrator recreates the container from the updated compose file. Expect
  `action_not_allowed` on those actions until then.

## Upgrading

Change the digest in `docker-compose.yml` to the new release's multi-arch
index digest (`docker buildx imagetools inspect ghcr.io/oomol-lab/open-connector:<tag>`),
run `docker compose … run --rm open-connector migrate` when the release notes
list pending migrations, then `start` and `probe`. Security fixes ship only on
the latest release, so do not stay pinned for long.
