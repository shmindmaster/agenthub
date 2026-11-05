# Bounded refresh

Read when: running `packages/repowise/scripts/Invoke-RepoWiseRefreshChanged.ps1` or `Invoke-RepoWiseBoundedIndex.ps1`, or reviewing Codex vendor hook ownership.

## Refresh what changed

`Invoke-RepoWiseRefreshChanged.ps1` compares each workspace entry's last synced commit with HEAD, inside that entry's folder, so a commit elsewhere in a monorepo does not count. Unchanged entries are never started. Changed entries run one at a time through the bounded wrapper, smallest first, each with 1800 s. `-DryRun` lists them. A repeat within 20 hours returns without visiting anything (`-MinimumHours`, `-Force`), so a capability can call it freely. `-Only <path>` limits it to named entries. Failures are listed and do not stop the rest, and a run where every visit failed does not count toward the 20 hours. A lease left by a killed run is cleared; a lease held by a live run or kept after exit 3 stops the run with `stopped` in its report. It registers no schedule.

A refresh updates symbols, graph, git history and health, and re-renders the affected wiki pages. It calls no model; pages embed through Azure. `-FactsOnly` skips pages and Azure for an outage. It saves about 7 of 31 s on a one-file change, and it cannot clear the upgrade state below.

The first refresh after a RepoWise version upgrade re-scores every repo in full, so it costs far more than a normal delta. A rendered run clears that state in one pass. After a `-FactsOnly` run it stays set, and every later run repeats the full re-score.

## Refresh one repo

Pass absolute `-Workspace`, `-RepositoryRoot`, `-LeasePath`, `-OutputDirectory` and a timezone-bearing `-Deadline`. Use the shared heavy-work lease path; a foreign lease is a refusal.

The wrapper updates one repo, index-only, with no agent generation, inside a Windows Job Object. A monorepo folder qualifies when the workspace file lists it. Defaults: 4 GiB aggregate commit-memory ceiling, 900 s, more than 4 GiB free physical RAM to start. A started job stops only after 10 s below 1 GiB free, because single samples here swing by gigabytes; the deadline shortens the budget. The owner may waive the free-RAM floor with `-RamFloorWaiverReason` (1-512 nonblank characters); it waives only the free-RAM checks, applies to that task alone, and is recorded in the lease and receipt.

Receipts and logs must resolve, junctions and symlinks followed, beneath `%LOCALAPPDATA%/AgentHub` and outside the source workspace; any other `-OutputDirectory` is refused and no receipt is written. The child uses the shared server's Azure embedding probe (same deployment and width); with `-FactsOnly` nothing leaves the machine. It runs hidden via `System.Diagnostics.Process`. It starts or stops no service and schedules nothing.

The wrapper refuses unless `.repowise/config.yaml` already sets `editor_files.claude_md: false` (and `agents_md: false` where applicable), because `update` regenerates those files otherwise. It never writes that config; creating it is the owner's per-repo decision. Submodules are fenced by gitlink commit and checked-out HEAD.

## Accept the result

Exit zero, no owned descendants left, exact HEAD recorded in `state.last_sync_commit`, and HEAD, staged files, tracked and non-ignored source, and known agent config unchanged. An unexpected source edit fails the run and is never silently reverted. The source fence covers Git-visible files plus `.vscode/mcp.json`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md` and `.repowise/config.yaml`.

The wrapper removes the lease only when no owned process remains. After exit 3 the lease stays; verify before removing it. If the wrapper is killed, the job dies with it. It is incremental only, not a provider migration or full rebuild.

## Fleet check

`pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All` verifies roster membership, hooks, freshness and the knowledge standard. See `docs/development/repo-standard.md`.

## Codex vendor hooks

The vendor `codex@repowise` plugin owns SessionStart and both PostToolUse hooks. Review and trust them through native `/hooks`; content changes require fresh review. Do not recreate a custom startup hook or duplicate user configuration. Vendor refresh suggestions remain subject to the bounded manual indexing contract above.
