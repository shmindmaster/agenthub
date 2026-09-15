# AgentHub — Product Vision

AgentHub is one personal control plane for consistent skills, plugins, MCP
servers, and policy across all coding-agent hosts in the fleet.

## Purpose

- `packages/<name>/` holds every **AgentHub-owned** capability; the registry
  distinguishes installable plugins from portable skill packs. Official
  third-party plugins and skills (Superpowers, Firecrawl, Clerk, Railway,
  Framer, Remotion, and similar) stay at their upstream and are tracked in
  `registry/native-connectors.json` -> `thirdPartyExtensions`. AgentHub may
  overlay fleet policy on top of them; it must not republish or pin a copy.
- Product repositories never contain plugin code, video tooling, or generated
  experience artifacts.
- The portable control plane is `policy-core.md` plus `registry/` templates.
  Owner identity, local runtime roots, and private evidence stay in
  `overlays/personal/` and are not part of a public-core export.
- Everything generated at runtime lives under `%LOCALAPPDATA%\AgentHub`.
- Local AI runtimes, models, caches, and media live only under `D:\Local-AI`.

## Boundaries

Keep only canonical source and deterministic validation here. Never add:
reports, logs, inventories, handoffs, session state, snapshots, or dated
evidence; `node_modules`, browser profiles, traces, recordings, rendered
media, or temporary workspaces; per-product `_product-experience`,
`_production`, `studio`, or video packages; duplicate plugin roots.

## Fleet-standard ownership

Since 2026-08-08 AgentHub also owns the fleet repository standard:
`registry/repo-standard.json` (roster + rules),
`scripts/Check-RepoStandard.ps1` (enforcement), and the `repowise` capability
(`packages/repowise/`, one shared workspace MCP for code intelligence)
and the documents layer (`packages/knowledge-access`, folders `01`–`06`
and `10` under the owner's Documents tree; records stay out of this repository).
