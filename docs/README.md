# Documentation Map

Start with [current-state.md](./current-state.md) for verified repository
reality. Everything else is durable knowledge, routed below.

## Product

- [product/vision.md](./product/vision.md) — what AgentHub is for, its
  boundaries, and what must never enter this repository. Read before adding a
  capability or a registry surface.
- Document intelligence for `D:\OneDrive - MahumTech\Documents\` folders
  `01`–`06` and `10` is the `knowledge-access` capability
  (`packages/knowledge-access`). RepoWise does not cover that tree.

## Architecture

- [architecture/overview.md](./architecture/overview.md) — the registry model,
  sync/deployment flow, and validation layers. Read before changing
  `registry/` or `scripts/`.
- [architecture/control-plane-modules.md](./architecture/control-plane-modules.md) —
  PathBinding, host catalog, capability overlay, and the public/personal split.

## Development

- [development/repo-standard.md](./development/repo-standard.md) — **the fleet
  repository standard** enforced by `scripts/Check-RepoStandard.ps1`. Read
  before touching any other repository under `C:\Repos\shmindmaster`.
- [development/setup.md](./development/setup.md) — environment and first-run
  requirements.
- [development/testing.md](./development/testing.md) — test layers and the
  canonical commands.
- [development/chrome-cdp.md](./development/chrome-cdp.md) — Playwright MCP
  fleet notes and plugin-gated playwright / chrome-devtools (browser-toolkit).

## Operations

- [runbooks/sync-and-validate.md](./runbooks/sync-and-validate.md) — drift
  audit, deploy, validate, and fleet standard sweep procedures.

## Execution

- [plans/PLANS.md](./plans/PLANS.md) — when and how to write resumable plans.
- [plans/active/](./plans/active/) — active complex work.
- [plans/completed/](./plans/completed/) — required directory; finished plans are deleted, not retained.
