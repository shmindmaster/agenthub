# shwiki-context

Portfolio context control plane for coding agents. Owned capability name: **`shwiki-context`**.

ShWiki is not the ultimate source of truth. Prefer current source code, tests, manifests, CI, and deployment configuration over generated wiki prose. Use ShWiki for cross-repository context, provenance, freshness, documentation gaps, and bounded commit-pinned source evidence.

## Transports

| Mode | Endpoint / command | Auth |
| --- | --- | --- |
| Local stdio (canonical on this workstation) | `pnpm --dir C:/Repos/shmindmaster/shwiki mcp:wiki` | None |
| Remote hosted snapshot (fallback) | `https://shwiki.shtrial.com/api/mcp` | Host-managed bearer/session |

Canonical MCP server name on every host: **`shwiki-context`**. Do not put tokens or Authorization headers in this package or checked-in host configuration.

## MCP surface

The supported contract is exactly eight read-only tools:

`wiki.catalog`, `wiki.search`, `wiki.get`, `wiki.analyze`, `repo.inspect`, `repo.read`, `repo.search`, and `repo.compare`.

There are no documentation-proposal or mutation tools. Repository documentation changes use the normal authorized coding workflow.

## Scheduler

The hourly Windows task **ShWiki Local Index** safely updates registered local clones, regenerates local artifacts, and runs the sensitive-content scan. It preserves wrong-branch, dirty, ahead, diverged, or unavailable checkouts and never commits or pushes.

## Skill and registration

- Canonical skill: [`skills/shwiki-context/SKILL.md`](./skills/shwiki-context/SKILL.md)
- Canonical local MCP registration: `registry/mcps.json`
- Hosted fallback metadata: `registry/mcp-registrations.json`
- Host adapters remain thin packaging only.

## Health checks

1. Local MCP contract: `pwsh -File C:\Repos\agent-capabilities\scripts\Test-ShwikiLocalContract.ps1`.
2. Local catalog: call `wiki.catalog` with `{ "view": "repositories" }`.
3. Local repository evidence: call `repo.inspect` with `{ "repository": "tellgence-backend", "operation": "status" }`.
4. Registry: `pwsh -File C:\Repos\agent-capabilities\tests\Validate-AgentEcosystem.ps1 -IncludeGlobalInstructions`.
5. Host rollout: `pwsh -File C:\Repos\agent-capabilities\scripts\Sync-AgentCapabilities.ps1 -Apply -Validate`.

## Security

- Read-only tools only.
- No anonymous hosted repository enumeration.
- No secrets, restricted source bodies, request payloads, or bearer tokens in logs or registry files.
- Local index refresh is separate from MCP and requires an explicitly authorized operator action.

## Related source

- ShWiki repository: `C:/Repos/shmindmaster/shwiki`
- Implementation plan: `docs/superpowers/plans/2026-07-21-mcp-surface-local-scheduler.md` in that repository
