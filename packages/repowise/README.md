# AH-RepoWise

Legacy-host RepoWise workspace bridge and bounded indexing tools. One skill plus the loopback shared server.

Claude and Codex use the vendor `repowise-dev/repowise` plugins instead; never install this wrapper alongside them. Other hosts keep the bridge until they are migrated.

Refresh the index only through `scripts/Invoke-RepoWiseBoundedIndex.ps1`. There is no post-commit hook and no bare `repowise update`. Root `plugin.json` is the version authority; bump it with `scripts/Bump-PackageVersion.ps1` and recompute this package's `contentHash` afterwards. See `docs/development/agent-repowise.md`.
