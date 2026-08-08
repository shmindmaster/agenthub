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

One workspace at the fleet root indexes all owned repos; the
`repowise-workspace` MCP entry (stdio, on-demand-local) is the single agent
surface. Workspace YAML lives at the fleet root (unversioned container);
the versioned declaration of the arrangement is this file plus
`registry/mcps.json` and `registry/repo-standard.json`.
