Read this before broad code exploration, when querying RepoWise, or when refreshing or updating the RepoWise index or CLI.

# AgentHub — RepoWise workflow

## Workspace

This repo is the primary (default) member of the RepoWise workspace at `C:\Repos`. The workspace covers `shmindmaster`, `sh-pendoah`, `musa-dev-team`, and `pendoah`.

## Querying

Before broad exploration, do one of the following:
- Use the workspace MCP `repowise-workspace`, which is registered in `registry/mcps.json`.
- Run `repowise search` or `repowise status -w` from `C:\Repos`.

Verify important derived claims against source.

## Refreshing the index

After material changes, refresh the index only through the bounded manual entry point `packages/repowise/scripts/Invoke-RepoWiseBoundedIndex.ps1`. There is no post-commit hook. Do not run bare `repowise update`.

A refreshed index is part of the definition of done.

## Updating the CLI

This is a manual step that updates the CLI to the latest PyPI release. There is no scheduled task.

```powershell
pwsh -NoProfile -File .\scripts\Update-RepoWise.ps1 -Apply
```

## Status of the package

RepoWise is a tracked public package (`packages/repowise`) and stays enabled for fleet code intelligence. Do not treat it as a private overlay item or disable it as part of overlay work.

## Full contract

[`packages/repowise/skills/use-repowise/SKILL.md`](../../packages/repowise/skills/use-repowise/SKILL.md)
