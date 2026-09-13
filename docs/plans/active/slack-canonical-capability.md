# Plan: Canonical Slack capability (2026-09-10)

## Purpose / outcome

Slack is one AgentHub-owned workspace capability. Every coding-agent host
is a frontend to the same tools, JSON schemas, identity, and lossless
objects. Host-native Slack plugins are optional UX, never the read/write
authority.

## Verified state at start (2026-09-10)

- No `packages/slack`. No `slack` id in `registry/capabilities.json` or
  `registry/mcps.json`.
- `registry/native-connectors.json` records the 2026-08-05 removal of the
  claude.ai account-level Slack connector. That removal stands. This plan
  does not restore that connector.
- Slack's official hosted MCP exists and is AI-oriented, not a lossless
  Web API. Official plugin wiring is uneven (Claude/Cursor get MCP; Codex
  plugin is skills-only; `npx skills` installs skills only).
- `gateway-profiles.json` describes one authenticated loopback streaming
  endpoint at `http://127.0.0.1:8811/mcp`, with `generationEnabled: false`
  until production evidence exists. That remains the intended distribution
  for Slack; it is not enabled by this plan.

## Target observable behavior

- Canonical tool inventory and input schemas live in
  `packages/slack/schemas/tools.json`.
- `slackContractHash = sha256(sorted tool names + canonical JSON schemas)`.
- A stdio MCP server (protocol 2025-11-25) implements those tools against
  the Slack Web API, preserving original Slack objects under `raw`.
- Fixture mode proves the contract without a live workspace or token.
- Skills deploy to every mapped host. MCP is plugin-gated / OpenCode
  opt-in-disabled until the gateway is production-proven.
- Official `slackapi/slack-skills-plugin` is tracked as optional UX, not
  republished, and is not the Slack owner.

## Exclusions

- No Slack app creation, OAuth grant, or token storage in this repository.
- No `Sync-AgentHub.ps1 -Apply` (host config write) until asked.
- No enabling of gateway `generationEnabled`.
- No restore of the claude.ai Slack connector.
- No live Slack write against a real workspace from tests.

## Milestones

1. [x] Canonical package, tool contract, fixture MCP, registry, tests.
2. [ ] Owner creates one AgentHub Slack app and user-OAuth grant.
       Record env refs only (`SLACK_USER_TOKEN`, optional `SLACK_BOT_TOKEN`).
3. [ ] Live read smoke against a synthetic/private channel (not customer
       data). Record protocol verification against the live Web API.
4. [ ] Gateway routes the same Slack contract (local `127.0.0.1:8811/mcp`
       and a remote authenticated endpoint for cloud agents). Then, and
       only then, consider session-start shared-remote persistence.
5. [ ] Host conformance: every managed host reports the same
       `slackContractHash`. Write roundtrip against fixture remains the
       CI gate; live write roundtrip is owner-authorized.

## Validation per milestone

- M1: `Validate-AgentHub.ps1`; `tests/Test-SlackCapability.ps1`;
  `tests/Test-SlackToolContract.ps1`; `tests/Test-SlackHostParity.ps1`;
  `tests/Test-OptInDisabledMcp.ps1`; `tests/Test-PluginManifests.ps1`;
  `tests/Run-AllTests.ps1`.
- M2: env refs present; no secret values in git.
- M3: dated `protocol.verification` against live `auth.test`.
- M4: gateway mapping `proofState` other than
  `contract-defined-not-yet-gateway-routed`; `generationEnabled` still
  requires the existing activationGuard evidence.
- M5: per-host hash evidence files under `%LOCALAPPDATA%\AgentHub`
  (never in this repo).

## Files expected to change

- `packages/slack/**`
- `registry/capabilities.json`, `mcps.json`, `gateway-profiles.json`,
  `native-connectors.json`, `bundles.json`
- `.agents/plugins/marketplace.json`, `.claude-plugin/marketplace.json`
- `tests/Test-Slack*.ps1`, `tests/Test-OptInDisabledMcp.ps1`
- `docs/current-state.md`, `docs/architecture/overview.md`, this plan

## Risks / rollback

- Plugin-gated delivery is not yet "every host sees Slack at session
  start". That is intentional: persisting stdio Slack would fan out
  processes the way Playwright did. Gateway is the fix, not host config.
- A live token in the environment could be used by an enabled plugin.
  Fixture tests never send network. Writes remain skill-gated.
- Rollback: revert the commit; do not Apply a partial registry.

## Decision log

- 2026-09-10: AgentHub owns Slack. Official Slack MCP is a reference
  implementation, not the fleet contract. Hydration is additive; IDs are
  never discarded. `actor_mode` is `user` (default) or `agent_bot`, never
  host-dependent. Current MCP delivery is on-demand-local / plugin-gated
  because gateway generation is still disabled.
