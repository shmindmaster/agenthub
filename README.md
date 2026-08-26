# AgentHub

One personal control plane for consistent skills, plugins, MCP servers, and policy across coding agents.

## Source of truth

- `packages/<name>/` contains every canonical capability. The registry distinguishes installable plugins from portable skill packs. Product repositories do not contain plugin code, video tooling, or generated experience artifacts.
- `registry/capabilities.json` declares capability ownership and host exposure.
- `registry/mcps.json` declares shared MCP servers using environment-variable or OAuth references, never credentials.
- `registry/agents.json` records host-native configuration paths and supported surfaces.
- `.agents/plugins/marketplace.json` is the canonical local catalog; `.claude-plugin/marketplace.json` is its minimal Claude-compatible projection for Claude, Factory, and Qwen installation.
- `registry/plugin-formats.json` records which hosts consume the shared package directly and which require loose skills/MCP instead of a fabricated manifest.
- `registry/product-video-delivery.json` maps finished video products to OneDrive.

Everything generated at runtime belongs under `%LOCALAPPDATA%\AgentHub`; it is never written into this repository. Sync keeps one replace-in-place `latest-drift.json`, not a report history. Local AI runtimes, models, caches, and media artifacts live only under `D:\Local-AI`.

## Commands

```powershell
# Read-only validation
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1

# Read-only drift audit
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate

# Full test suite
pwsh -NoProfile -File .\tests\Run-AllTests.ps1

# Fleet repository-standard sweep (report / repair)
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All -Fix

# Apply canonical loose-skill distribution
pwsh -NoProfile -File .\scripts\Sync-Capabilities.ps1 -Apply

# Apply managed instructions and MCP configuration
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Apply -Validate
```

## Documentation

Curated knowledge lives under [`docs/`](./docs/README.md): the fleet
repository standard, architecture, testing, and runbooks.

## Codebase intelligence

This repo is the primary member of the fleet RepoWise workspace
(`C:\Repos\shmindmaster`), which provides generated documentation,
dependency/history analysis, code health, and one MCP server
(`repowise-workspace` in `registry/mcps.json`) for coding agents.

Useful commands (from the fleet root):

- `repowise status -w`
- `repowise update -w`
- `repowise serve`  (local dashboard + MCP)

`Sync-Capabilities.ps1` owns loose-skill distribution. `Sync-AgentHub.ps1` owns MCP and instruction deployment plus the documented Qwen compatibility projection. Native plugin installation remains host-managed from the canonical catalog and its Claude-compatible projection; no script invents a host plugin format.

## Repository boundary

Keep only canonical source and deterministic validation here. Do not add:

- reports, logs, inventories, handoffs, session state, snapshots, or dated evidence;
- `node_modules`, browser profiles, traces, recordings, rendered media, or temporary workspaces;
- per-product `_product-experience`, `_production`, `studio`, or video packages;
- duplicate `portfolio-plugins`, `handoff-plugins`, `capabilities`, `adapters`, or `generated` roots.

Media Studio is the public video/audio pack (`packages/media-studio`). Live-product screencasts still invoke the internal engine in `packages/product-demo-studio`. Runtime workspaces live under `%LOCALAPPDATA%\AgentHub\media-studio` and `%LOCALAPPDATA%\AgentHub\product-demo-studio`. Approved media delivers to the OneDrive destination in `registry/product-video-delivery.json`.
