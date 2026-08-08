# AgentHub — Repository Agent Guide

## Mission

AgentHub is the personal source of truth for cross-agent skill, plugin, MCP,
and policy parity, and the owner of the fleet repository standard
(`registry/repo-standard.json` + `scripts/Check-RepoStandard.ps1`).

Optimize in this order:

1. Correct registry↔deployment parity (no undetected drift).
2. Security: never centralize credentials, customer data, or private evidence.
3. Honest recorded state (`false` = checked-absent, `null` = not established).
4. Deterministic validation over re-derivation by agents.
5. Maintainability and simplicity.

## Knowledge authority

Executable code/tests/scripts describe implemented reality. `docs/` holds
intentional durable knowledge. RepoWise holds derived codebase intelligence.
When they disagree, investigate rather than silently choosing one.

## Start here

1. This file (`AGENTS.md`).
2. `docs/README.md` → `docs/current-state.md`.
3. `global-agent-policy.md` — the canonical compiled global policy.
4. `docs/development/repo-standard.md` when touching any other fleet repo.
5. `registry/` entries relevant to the capability you are changing.
6. RepoWise workspace context before broad exploration.

## RepoWise workflow

This repo is the primary (default) member of the fleet workspace at
`C:\Repos\shmindmaster`. Use the workspace MCP (`repowise-workspace`,
registered in `registry/mcps.json`) or `repowise search`/`status` before
broad exploration. After material changes, run `repowise update --repo agenthub`
if the post-commit hook has not already refreshed the index. Verify important
derived claims against source. Full contract:
[`packages/repowise/skills/use-repowise/SKILL.md`](./packages/repowise/skills/use-repowise/SKILL.md).

## Repository map

| Path | Role |
| --- | --- |
| `packages/<name>/` | Canonical capability content (skill packs, plugins) |
| `registry/` | Parity contract: agents, capabilities, MCPs, fleet profile, repo standard |
| `scripts/` | Lifecycle: sync, validate, hash, checker |
| `tests/` | Behavior tests for registry, sync, and scripts |
| `docs/` | Curated durable knowledge — see `docs/README.md` |
| `.agents/plugins/marketplace.json` | Canonical local plugin catalog |
| `.claude-plugin/marketplace.json` | Claude-format compatibility projection |

## Canonical commands

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1          # registry validation
pwsh -NoProfile -File .\tests\Run-AllTests.ps1                 # full test suite
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All    # fleet standard check
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate   # drift audit
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Apply -Validate   # deploy managed state
```

## Boundary (non-negotiable)

- Personal capability work stays in personal systems and uses synthetic fixtures.
- Never copy credentials, authentication state, customer data, private evidence,
  reports, session state, generated media, or runtime caches into this repository.
- Read a target repository's `AGENTS.md` before touching it. Preserve unrelated work.
- Ask before production changes, external communication, credential changes, or
  destructive work unless the user explicitly authorized it.
- Do not reintroduce `adapters`, `capabilities`, `generated`, `profiles`,
  `reports`, `roles`, `standards`, `state`, `templates`, nested plugin roots,
  or dated audit documents. (`docs/` is permitted: it carries the curated
  taxonomy required by the fleet standard since 2026-08-08.)
- Runtime output belongs under `%LOCALAPPDATA%\AgentHub`. Local AI runtimes,
  models, caches, and media live only under `D:\Local-AI`.

## Change contract

Before changing a capability, identify its single registry owner. Update
canonical package content and every applicable host manifest, bump package
versions, recompute the registry content hash with
`scripts/RegistryContentHash.ps1`, and run `scripts/Validate-AgentHub.ps1`
plus the package's own validator.

`scripts/AgentHub.ps1` is the single lifecycle entry point: `inventory`,
`validate`, `sync` (audits by default; `-Apply` refuses to run if validate
fails), and `drift`. It orchestrates the existing scripts; it does not
reimplement them.

Use official host formats. A host without verified packaging support receives
supported loose skills/MCP configuration; do not invent a plugin format. Keep
implemented, validated, deployed, and production-verified states distinct.

## Tracker

None. This repo is the fleet's policy/control plane; work is driven by drift
detection and validation, not an external backlog. Complex multi-session work
uses `docs/plans/active/`.

## Testing and verification

- Every registry or script change: `Validate-AgentHub.ps1` + affected
  `tests/Test-*.ps1` (or the full `tests/Run-AllTests.ps1` when shared
  contracts move).
- The fleet checker has fixture tests: `tests/Test-RepoStandard.ps1`.
- Never claim a check passed unless it ran.

## Safety

- Never commit secrets, tokens, or credentials; registry entries reference
  environment variables, never values.
- Never erase unrelated local work.
- Never rewrite history.
- Do not weaken host/auth/credential boundaries to make validation pass.

## Definition of done

- Registry and package content agree; content hashes recomputed.
- `Validate-AgentHub.ps1` and relevant tests pass.
- Docs updated when behavior, layout, or contracts changed.
- RepoWise index refreshed (hook or manual update).

## GitHub

Use `gh`, verify the active account first, and use `shmindmaster` for this
repository. Direct commits to `main` are the default path.
