# Architecture Overview

## The registry model

`registry/*.json` is the parity contract between canonical package content
and per-host deployment:

- `agents.json` — host-native config paths, surfaces, instruction files.
- `capabilities.json` — capability ownership, canonical sources, content
  hashes (over git-tracked files), per-host deployment status.
- `mcps.json` — shared MCP servers with environment/OAuth credential
  references (never values), protocol-revision evidence, activation policy.
- `fleet-profile.json` — dispatch policy, autonomy profiles, host surfaces.
- `repo-standard.json` — fleet repository roster + standard rule parameters
  for the checker.
- `mobile-scope.json` — which products may receive native mobile work, and
  which have their mobile identity frozen pending repositioning. Absence from
  it never means eligible; `tests/Test-MobileScope.ps1` fails on any
  unclassified fleet repository.
- `plugin-formats.json`, `subagent-formats.json`, `native-connectors.json`,
  `gateway-profiles.json`, `product-video-delivery.json` — host format and
  delivery records.

## Flow

```text
packages/<capability>  ──hash──▶  registry/capabilities.json
        │                                │
        ▼                                ▼
Sync-Capabilities.ps1            Sync-AgentHub.ps1
(loose skills to hosts)          (instructions + MCP config to hosts)
        │                                │
        └────── Validate-AgentHub.ps1 + tests/ keep both honest ──┘
```

- `scripts/AgentHub.ps1` is the lifecycle entry point
  (inventory / validate / sync / drift).
- `scripts/Check-RepoStandard.ps1` sweeps every fleet repo for the knowledge
  standard; `registry/repo-standard.json` is its roster.
- Content hashes are recomputed with `scripts/RegistryContentHash.ps1`
  whenever package content changes.

## RepoWise workspace

One workspace at `C:\Repos` indexes git repos under `shmindmaster`,
`sh-pendoah`, `musa-dev-team`, and `pendoah`; the `repowise-workspace` MCP
entry (stdio, on-demand-local, `repowise mcp C:/Repos`) is the single agent
surface. Workspace YAML lives at `C:\Repos` (unversioned container); the
versioned declaration of the arrangement is this file plus
`registry/mcps.json` and `registry/repo-standard.json`. Per-repo indexes
are stored in each repo's `.repowise/` directory.

## Knowledge-access documents layer

`packages/knowledge-access` is the sibling for curated documents under
`D:\OneDrive - MahumTech\Documents\` folders `02`–`06`. It is not a
RepoWise workspace: OneDrive is not a git root, and client names are an
output gate. Agents read `_MAP.md`, then exact-search, then specific
files. Runtime engagement records stay in the private
`C:\Repos\shmindmaster\portfolio-records` repository.
