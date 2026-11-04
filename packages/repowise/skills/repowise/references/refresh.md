# Bounded refresh

Read when: running `packages/repowise/scripts/Invoke-RepoWiseBoundedIndex.ps1` or reviewing Codex vendor hook ownership.

## Run it

Pass absolute `-Workspace`, `-RepositoryRoot`, `-LeasePath`, `-OutputDirectory` and a timezone-bearing `-Deadline`. Use the shared heavy-work lease path; a foreign lease is a refusal. Do not start during a closed heavy-work window.

The wrapper updates one repo, index-only, with no agent generation, inside a Windows Job Object. Defaults: 8 GiB aggregate commit-memory ceiling, 900 s, more than 8 GiB free physical RAM. Free RAM below the floor stops only the owned job; the deadline shortens the budget. The owner may waive the free-RAM floor with `-RamFloorWaiverReason` (1-512 nonblank characters); it waives only the free-RAM checks, applies to that task alone, and is recorded in the lease and receipt.

Receipts and logs must resolve, junctions and symlinks followed, beneath `%LOCALAPPDATA%/AgentHub` and outside the source workspace; any other `-OutputDirectory` is refused and no receipt is written. The child uses the shared server's Azure embedding probe (same deployment and width) and runs hidden via `System.Diagnostics.Process`. It starts or stops no service and schedules nothing.

The wrapper refuses unless `.repowise/config.yaml` already sets `editor_files.claude_md: false` (and `agents_md: false` where applicable), because `update` regenerates those files otherwise. It never writes that config; creating it is the owner's per-repo decision. Submodules are fenced by gitlink commit and checked-out HEAD.

## Accept the result

Exit zero, no owned descendants left, exact HEAD recorded in `state.last_sync_commit`, and HEAD, staged files, tracked and non-ignored source, and known agent config unchanged. An unexpected source edit fails the run and is never silently reverted. The source fence covers Git-visible files plus `.vscode/mcp.json`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md` and `.repowise/config.yaml`.

The wrapper removes the lease only when no owned process remains. After exit 3 the lease stays; verify before removing it. If the wrapper is killed, the job dies with it. It is incremental only, not a provider migration or full rebuild.

## Fleet check

`pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All` verifies roster membership, hooks, freshness and the knowledge standard. See `docs/development/repo-standard.md`.

## Codex vendor hooks

The vendor `codex@repowise` plugin owns SessionStart and both PostToolUse hooks. Review and trust them through native `/hooks`; content changes require fresh review. Do not recreate a custom startup hook or duplicate user configuration. Vendor refresh suggestions remain subject to the bounded manual indexing contract above.
