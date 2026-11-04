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

This is a manual step that updates the CLI to the latest PyPI release. There is no scheduled task. The updater compares versions first and replaces an obsolete exact uv requirement with `repowise@latest` only when behind. It does not initialize editors, rewrite hooks, or reinstall a current package. `-RepairHooks` is a separate explicit legacy repair.

```powershell
pwsh -NoProfile -File .\scripts\Update-RepoWise.ps1 -Apply
```

## Status of the package

RepoWise remains a tracked public package (`packages/repowise`) for bounded indexing and legacy-host compatibility. Claude uses the vendor `repowise@repowise` plugin and Codex uses `codex@repowise`, from `https://github.com/repowise-dev/repowise`. Both use the existing C:/Repos workspace. On these hosts uninstall the old `repowise@agenthub` wrapper and remove duplicate user hooks; never restore them as parity repair. Other hosts keep their existing bridge until migrated. Useful personal AgentHub plugins remain separate and approved.

Vendor hooks belong to the plugin. Codex reviews and trusts them through `/hooks`; changed hook content requires fresh review. Do not write trust hashes manually. Keep the bounded indexing rule above even when vendor guidance suggests bare `repowise update`.

## Full contract

[`packages/repowise/skills/repowise/SKILL.md`](../../packages/repowise/skills/repowise/SKILL.md)
