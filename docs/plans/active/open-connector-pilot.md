# Plan: OpenConnector fleet gateway pilot (2026-09-12)

## Purpose / outcome

One self-hosted OpenConnector container (`registry/mcps.json#open-connector`)
gives the non-Claude agent hosts (codex, cursor, opencode, grok) a single
shared HTTP MCP for owner-credentialed SaaS actions, replacing one stdio
bridge per host per provider. Claude Code keeps its first-party connectors.
Products do not use it. Assessment:
[OpenConnector Fit Assessment](https://claude.ai/code/artifact/1c336229-6774-4e2b-9a20-139111ae1d22).

## Verified state at start (2026-09-12)

- Image `ghcr.io/oomol-lab/open-connector` v1.5.0 (index digest
  `sha256:b9e6133c…`, built 2026-09-04) runs on this machine from
  `packages/open-connector/docker-compose.yml`, bound to `127.0.0.1:3400`,
  SQLite under `%LOCALAPPDATA%\AgentHub\runtime\open-connector\data`.
- Probed: MCP `initialize` → `protocolVersion 2025-11-25`; five tools;
  unauthenticated `/mcp` and `/v1/health` → 401; out-of-allowlist action →
  `400 action_not_allowed`; runtime-token create/accept/revoke/refuse passes.
- `PUT /api/connections/{service}` verifies the credential against the
  provider on connect (a throwaway github key was refused), so connecting is
  an outbound call, not a local write.
- No connections exist. No runtime tokens exist beyond the bootstrap one in
  the runtime env file. Nothing is written to any host config.
- All eleven SaaS-facing ids already in `registry/mcps.json` (github, linear,
  notion, slack, linkedin, descript, railway, context7, firecrawl, exa,
  brave-search) have a provider in the v1.5.0 catalog (1,465 providers).

## Target observable behavior

1. A Codex session lists `open-connector` tools and can run a read action
   (for example `linear.list_issues`) against the owner's connected account
   with a codex-scoped runtime token, with no stdio process spawned.
2. `Test-DeclaredVsDeployedMcp` passes with codex recorded as a persisted
   host for the id, and `Check-LocalMcpInstancing` shows one container, no
   per-host processes.
3. Resident memory of the replaced stdio bridges on codex is measured before
   and after (same method as the 2026-08-19 and 2026-09-07 measurements in
   `registry/native-connectors.json`).
4. `exit-test` and a real connection revoke both pass before any provider is
   connected with a non-throwaway credential.

## Exclusions

- No Claude Code deployment. No product repository changes. No tenant or
  customer credentials in the gateway.
- Existing `github`/`linear`/`notion`/… registrations stay as they are; this
  id coexists. Taking over an id on a host is a separate owner decision.
- The raw provider proxy stays blocked (`OOMOL_CONNECT_BLOCKED_PROXIES=*`).
- No hosted OOMOL OAuth apps; every OAuth provider uses an owner-registered
  app.

## Milestones

| # | Milestone | Validation |
| --- | --- | --- |
| 1 | Package, registry entries, runbook (this change) | `Validate-AgentHub.ps1`, `Run-AllTests.ps1` from the worktree; content hash recomputed |
| 2 | Owner connects one read-mostly provider (Linear or GitHub) via the console with an owner OAuth app; mints `codex` token with `linear.*`/`github.*` read actions | `Invoke-OpenConnector.ps1 probe`; `list_connections` shows the account |
| 3 | Persist for codex: add `open-connector` to `persistedOnDemandLocalMcpIds`, record codex `shared-gateway` exposure, `Sync-AgentHub.ps1 -Apply -Validate` from the main checkout | `Test-DeclaredVsDeployedMcp` green; Codex `config.toml` carries the entry with `bearer_token_env_var` |
| 4 | Measure: process count and RSS with the stdio bridges removed from codex | Numbers recorded in `native-connectors.json` evidence |
| 5 | Decide: extend to cursor/opencode/grok, or stop and roll back | Decision log below |

## Files expected to change

- `packages/open-connector/**` (new), `registry/mcps.json`,
  `registry/capabilities.json`, `registry/native-connectors.json`
  (milestone 1 — done in this change).
- `registry/native-connectors.json` (`persistedOnDemandLocalMcpIds`, codex
  exposure) at milestone 3.
- Codex `config.toml` via sync at milestone 3 (not by hand).

## Risks and rollback

- Single-owner runtime: one admin token and one AES key guard every stored
  credential. Mitigation: loopback bind, per-host tokens with explicit
  allowlists, proxy blocked, no tenant data ever.
- 1,465 in-process provider modules; security fixes ship on the latest
  release only. Mitigation: digest pin, upgrade with `migrate` then `probe`.
- Rollback: remove the id from `persistedOnDemandLocalMcpIds`, run sync
  `-Apply`, `Invoke-OpenConnector.ps1 stop`. Stored connections remain in
  the data directory until revoked through the admin API or the directory
  is deleted; delete only after the exit test passes.

## Progress

- 2026-09-12: milestone 1 built in worktree `C:\wt\agenthub\open-connector-pilot`
  (branch `worktree-open-connector-pilot`). Container started and probed; wrapper
  verbs `start`/`status`/`probe`/`exit-test`/`mint-token` exercised; all
  throwaway tokens revoked. Not committed, not merged, not deployed.
- 2026-09-12 (later): merged to `main` as #17 (`25eda7f`); worktree and
  branch removed. Local main reconciled with the in-flight Slack/OSS
  extraction work (two additive JSON conflicts in `capabilities.json` and
  `native-connectors.json` resolved; snapshot tag
  `backup/main-inflight-20260912`). **Still not deployed**, and not
  deployable from this tree yet: `Validate-AgentHub.ps1` fails on
  `media-studio` content-hash drift and the in-flight
  `scripts/Sync-AgentHub.ps1` refactor errors in audit mode
  (`Get-AgentHubIsolatedLocalData`: "Cannot overwrite variable Home"). Both
  pre-date this plan; `-Apply` refuses until they are fixed. Milestones 2–3
  unchanged.

## Decision log

- 2026-09-12: coexist, do not take over ids. The pilot adds a route for
  non-Claude hosts and leaves every existing registration untouched.
- 2026-09-12: `on-demand-local` + `transport: http`, not persisted. The
  container is a standing local service the owner starts, not a
  host-spawned process, so persisting later starts nothing at session
  start; until then the `hosts[]` list is eligibility only.
- 2026-09-12: products stay direct. Lawli SH-2748, LienWise
  `external-platforms.policy.js`, and CoLedger `ai-boundaries.md` already
  record this; the gateway's schema (single owner) confirms it.
