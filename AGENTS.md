# AgentHub — Repository Agent Guide

## Mission

AgentHub is the **public** source of truth for cross-agent skill, plugin, MCP, and policy parity. It owns the fleet repository standard (`registry/repo-standard.json` + `scripts/Check-RepoStandard.ps1`).

Priorities, in order:
1. Registry↔deployment parity with no undetected drift.
2. Security: never centralize credentials, customer data, or private evidence.
3. Honest recorded state (`false` = checked-absent, `null` = not established).
4. Deterministic validation over re-derivation by agents.
5. Maintainability and simplicity.

**Public-first:** only public packages under `packages/` are tracked. Private capability packages and registry rows live only in the private overlay: its own clone of `shmindmaster/agenthub-private` beside this checkout (`C:/Repos/shmindmaster/agenthub-private`), or the gitignored `overlays/personal/` where one exists, or `AGENTHUB_OVERLAY`. There is no second control-plane repo. Do not recreate one. RepoWise is retired (owner decision 2026-11-13, SH-4409): do not install, restore or add it, and do not require it. It was removed from AgentHub and every host under SH-4670. Repository knowledge moves to local, host-driven OpenWiki (SH-4410). Preserve useful personal AgentHub media, product and owner workflows.

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
- Do not run, refresh or reinstall RepoWise. No post-commit hook, no bare `repowise update`. Upstream `openwiki/` output and its scoped managed discovery blocks in AGENTS.md/CLAUDE.md are the one permitted exception to the no-new-directories rule above; they are generated only by an explicit host-driven OpenWiki update, never at session start.
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

Use the [AgentHub — Portfolio Engineering & Knowledge project](https://linear.app/abacare/project/agenthub-portfolio-engineering-and-knowledge-a780cf63463d) in ABACARE's Shared Platform team for project-wide work. Claim the relevant issue with `agent:<host>` before editing. Git holds code, configuration and docs. Linear holds scope, claims and dependencies. Drift detection and validation remain the correctness authority. Complex multi-session work may add `docs/plans/active/` that references issue IDs.

## Definition of done

- Registry and package content agree; content hashes recomputed.
- `Validate-AgentHub.ps1` and relevant tests pass.
- Docs updated when behavior, layout, or contracts changed.
- Affected `openwiki/` pages refreshed through the host-driven integration once it exists (SH-4410); a missing or stale wiki never blocks work.

## GitHub

Use `gh` and verify the active account first. Use `shmindmaster` for this repo. Direct commits to `main` are the default.

## Load when

| Trigger | Read |
| --- | --- |
| Starting work, orienting, finding which doc/path owns what | [`docs/development/agent-orientation.md`](./docs/development/agent-orientation.md) |
| Broad code exploration | Native source search; read `openwiki/` pages when present |
| Changing a capability, registry, package, script, test, or host manifest; before declaring done | [`docs/development/agent-change-contract.md`](./docs/development/agent-change-contract.md) |
| Touching any other fleet repo | `docs/development/repo-standard.md` |
