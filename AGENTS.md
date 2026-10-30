# AgentHub — Repository Agent Guide

## Mission

AgentHub is the **public** source of truth for cross-agent skill, plugin, MCP, and policy parity. It owns the fleet repository standard (`registry/repo-standard.json` + `scripts/Check-RepoStandard.ps1`).

Priorities, in order:
1. Registry↔deployment parity with no undetected drift.
2. Security: never centralize credentials, customer data, or private evidence.
3. Honest recorded state (`false` = checked-absent, `null` = not established).
4. Deterministic validation over re-derivation by agents.
5. Maintainability and simplicity.

**Public-first:** only public packages under `packages/` are tracked. Private capability packages and registry rows live only in the gitignored `overlays/personal/`. There is no second control-plane repo. Do not recreate one. RepoWise (`packages/repowise`) is a public package and stays enabled. Never treat it as an overlay item or disable it during overlay work.

## Start here

1. This file, then `docs/README.md` → `docs/current-state.md`.
2. Open the reference a trigger in **Load when** (below) names before doing that kind of work.

## Safety and boundaries (non-negotiable)

- Never copy or commit credentials, secrets, tokens, auth state, customer data, private evidence, reports, session state, generated media, or runtime caches. Registry entries reference environment variables, never values. Personal capability work stays in personal systems and uses synthetic fixtures.
- Ask before production changes, external communication, credential changes, or destructive work unless the user explicitly authorized it.
- Read a target repo's `AGENTS.md` before touching it. Preserve and never erase unrelated local work. Never rewrite history.
- Do not weaken host/auth/credential boundaries to make validation pass.
- Do not reintroduce any of these:
  - `adapters`, `capabilities`, `generated`, `profiles`, `reports`, `roles`, `standards`, `state`, `templates`
  - nested plugin roots
  - dated audit documents

  `docs/` is permitted. It carries the curated fleet-standard taxonomy since 2026-08-08.
- No script registers a scheduled task, Run key, or auto-start service. Every launched subprocess is windowless (owner direction 2026-10-13; `global-agent-policy.md` → Engineering behavior). Local services start when the capability that needs them is used. Updates run manually.
- Runtime output goes under `%LOCALAPPDATA%\AgentHub`. Local AI is off; media production lives under `D:\Media-Studio` (env `MEDIA_STUDIO_ROOT`).
- Refresh the RepoWise index only via `packages/repowise/scripts/Invoke-RepoWiseBoundedIndex.ps1`. No post-commit hook, no bare `repowise update`.
- Never claim a check passed unless it ran.

## Canonical commands

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1                # registry validation
pwsh -NoProfile -File .\tests\Run-AllTests.ps1                       # full test suite
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All          # fleet standard check
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate   # drift audit
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Apply -Validate   # deploy managed state
```

## Tracker

None. Work is driven by drift detection and validation, not an external backlog. Complex multi-session work uses `docs/plans/active/`.

## Definition of done

- Registry and package content agree; content hashes recomputed.
- `Validate-AgentHub.ps1` and relevant tests pass.
- Docs updated when behavior, layout, or contracts changed.
- RepoWise index refreshed through the bounded manual entry point.

## GitHub

Use `gh` and verify the active account first. Use `shmindmaster` for this repo. Direct commits to `main` are the default.

## Load when

| Trigger | Read |
| --- | --- |
| Starting work, orienting, finding which doc/path owns what | [`docs/development/agent-orientation.md`](./docs/development/agent-orientation.md) |
| Broad code exploration, RepoWise queries, refreshing/updating RepoWise | [`docs/development/agent-repowise.md`](./docs/development/agent-repowise.md) |
| Changing a capability, registry, package, script, test, or host manifest; before declaring done | [`docs/development/agent-change-contract.md`](./docs/development/agent-change-contract.md) |
| Touching any other fleet repo | `docs/development/repo-standard.md` |