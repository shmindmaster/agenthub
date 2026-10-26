# Documentation Map

Start with [development/quickstart.md](./development/quickstart.md) for a
stranger-safe first run. For this private fleet checkout, also use
[current-state.md](./current-state.md) for verified repository reality.

## Product

- [product/vision.md](./product/vision.md) — what AgentHub is for, its
  boundaries, and what must never enter this repository. Read before adding a
  capability or a registry surface.

## Architecture

- [architecture/control-plane-modules.md](./architecture/control-plane-modules.md) —
  PathBinding, host catalog, capability overlay, and the public/personal split.
- [architecture/overview.md](./architecture/overview.md) — registry model and
  validation layers (fleet checkout).
- [architecture/portfolio-policy.md](./architecture/portfolio-policy.md) —
  proposed portfolio sharing policy (private).

## Development

- [development/quickstart.md](./development/quickstart.md) — init → validate → sync.
- [development/setup.md](./development/setup.md) — environment requirements.
- [development/testing.md](./development/testing.md) — test layers.
- [development/skill-authoring-standard.md](./development/skill-authoring-standard.md).
- [development/repo-standard.md](./development/repo-standard.md) — fleet repository standard.
- [development/agent-orientation.md](./development/agent-orientation.md), [agent-repowise.md](./development/agent-repowise.md), [agent-change-contract.md](./development/agent-change-contract.md) — agent reference loaded on demand from the triggers in `AGENTS.md`.
- [development/chrome-cdp.md](./development/chrome-cdp.md) — browser MCP notes.

## Operations

- [runbooks/sync-and-validate.md](./runbooks/sync-and-validate.md) — drift
  audit, deploy, validate, and fleet standard sweep procedures.
- [runbooks/demo-profile.md](./runbooks/demo-profile.md) — throwaway profile
  for an on-camera audit -> apply -> audit, with home paths cropped to `~`.
- [runbooks/stale-agent-sessions.md](./runbooks/stale-agent-sessions.md) —
  on-demand recycle of coding-agent sessions older than seven days, and where
  each agent keeps them.

## Execution

- [plans/PLANS.md](./plans/PLANS.md) — when and how to write resumable plans.
- [plans/active/](./plans/active/) — active complex work.
- [plans/completed/](./plans/completed/) — required directory; finished plans are deleted, not retained.

## Fleet

- [context-reduction.md](./fleet/context-reduction.md) — manual context audits,
  reversible skill cleanup and native on-demand tool discovery.
- [usage-diet-2026-10-26.md](./fleet/usage-diet-2026-10-26.md) — Claude Code
  startup-context measurements, plugins/connectors cut, rollback per change.
- [retired-hosts-2026-10-21.md](./fleet/retired-hosts-2026-10-21.md) — Qoder,
  Qwen Code, and Hermes retirement record.
- [account-logins-2026-10-21.md](./fleet/account-logins-2026-10-21.md) — host
  account-authentication commands and verified gates.
- [goal-setting-by-host-2026-10-21.md](./fleet/goal-setting-by-host-2026-10-21.md) — per-host
  goal and persistent-objective mechanisms, verified versions and sources.

## Proposals

- [proposals/media-studio-2.1-sync-and-build.md](./proposals/media-studio-2.1-sync-and-build.md) —
  proposed media-studio 2.1: word-synced text, diagrams that build on narration
  beats, emphasis role tokens, and the word-sync gate (review only).
- [proposals/windows-ui-automation-capability.md](./proposals/windows-ui-automation-capability.md) —
  proposed Windows UI Automation capability and Windows-MCP evaluation (review only).
