# open-connector

Fleet SaaS action gateway: one self-hosted
[oomol-lab/open-connector](https://github.com/oomol-lab/open-connector)
container on this machine, exposed to non-Claude agent hosts as a five-tool
MCP. Pilot, registered 2026-09-12. Assessment that led here:
[OpenConnector Fit Assessment](https://claude.ai/code/artifact/1c336229-6774-4e2b-9a20-139111ae1d22).

## What it is for

- Codex, Cursor, OpenCode, and Grok reach GitHub, Linear, Notion, Slack,
  Railway, Firecrawl, Exa, Brave Search, Descript, Context7, PostHog, Sentry,
  and DigitalOcean through one shared local HTTP process instead of one
  stdio bridge per host per provider.
- Claude Code keeps its first-party connectors; this MCP is not added there.
- Owner-only credentials. Not a product component, not a tenant credential
  store. See `skills/use-open-connector/SKILL.md` §1 for the boundary and the
  product decisions that fix it.

## Layout

| Path | Role |
| --- | --- |
| `docker-compose.yml` | Pinned image (v1.5.0 by digest), loopback bind, policy env |
| `.env.example` | Variable names for the runtime env file (no values) |
| `scripts/Invoke-OpenConnector.ps1` | `start` / `stop` / `status` / `probe` / `mint-token` / `exit-test` |
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
3. Connect providers through the console at `http://127.0.0.1:3400` (admin
   token). OAuth providers need your own OAuth app: read the redirect URI from
   `GET /api/oauth/configs`, register it with the provider, then
   `PUT /api/oauth/configs/{service}`. API-key providers are a single
   `PUT /api/connections/{service}`. Note that the runtime verifies a
   credential against the provider on connect.
4. Mint one persistent runtime token per host and retire the bootstrap one:
   `Invoke-OpenConnector.ps1 mint-token -Name codex -AllowedActions 'github.*','linear.*'`.
   The token is printed once. Put it in that host's environment as
   `OPEN_CONNECTOR_RUNTIME_TOKEN`; the registry entry references only the
   variable name.
5. `exit-test` proves revocation works before the gateway holds anything real.
6. Deployment to a host config is a separate, reviewed step: add
   `open-connector` to `registry/native-connectors.json →
   lifecyclePolicy.persistedOnDemandLocalMcpIds`, record the host's exposure,
   and run `scripts/Sync-AgentHub.ps1 -Apply -Validate` from the main
   checkout. Until then the registry entry is eligibility, not deployment.

## Policy defaults (compose)

- Bound to `127.0.0.1:3400`. Port 3000 is Duckie; 7337/7338 are RepoWise.
- `OOMOL_CONNECT_ALLOWED_ACTIONS` is an explicit provider allowlist; widen per
  provider, never to `*`.
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

## Upgrading

Change the digest in `docker-compose.yml` to the new release's multi-arch
index digest (`docker buildx imagetools inspect ghcr.io/oomol-lab/open-connector:<tag>`),
run `docker compose … run --rm open-connector migrate` when the release notes
list pending migrations, then `start` and `probe`. Security fixes ship only on
the latest release, so do not stay pinned for long.
