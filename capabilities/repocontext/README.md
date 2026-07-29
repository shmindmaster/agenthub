# RepoContext

Private portfolio context control plane for coding agents. Owned capability and MCP server name: **`repocontext`**.

RepoContext is not an authority above the indexed repositories. Prefer current source code, tests, manifests, CI, and deployment configuration. Use RepoContext for cross-repository discovery, provenance, documentation gaps, and bounded commit-pinned evidence.

## Transports

| Mode | Endpoint / command | Auth |
| --- | --- | --- |
| Local stdio (validated) | `pnpm --dir C:/Repos/shmindmaster/repocontext mcp:serve` | None |
| Private remote Streamable HTTP (deployment pending) | `https://repocontext.shtrial.com/api/mcp` | `REPOCONTEXT_MCP_TOKEN` in the host secret store |

The private remote service uses a generated, Git-only documentation/manifests snapshot. It excludes non-Git folders, dirty and untracked work, and any file flagged by the secret scan.

## MCP surface

The supported contract is exactly eight read-only tools:

`wiki.catalog`, `wiki.search`, `wiki.get`, `wiki.analyze`, `repo.inspect`, `repo.read`, `repo.search`, and `repo.compare`.

There are no documentation-proposal or mutation tools. Repository documentation changes use the normal authorized coding workflow.

## Skill and registration

- Canonical skill: [`skills/repocontext/SKILL.md`](./skills/repocontext/SKILL.md)
- Active local MCP registration: `registry/mcps.json`
- Pending hosted transport and local fallback metadata: `registry/mcp-registrations.json`
- Host adapters remain thin packaging only.

## Health checks

1. Local MCP contract: `pwsh -File C:\Repos\shmindmaster\agenthub\scripts\Test-RepoContextLocalContract.ps1`.
2. Local catalog: call `wiki.catalog` with `{ "view": "repositories" }`.
3. Local repository evidence: call `repo.inspect` with `{ "repository": "crewscore", "operation": "status" }`.
4. Registry: `pwsh -File C:\Repos\shmindmaster\agenthub\tests\Validate-AgentEcosystem.ps1 -IncludeGlobalInstructions`.
5. Remote contract after deployment: set `REPOCONTEXT_MCP_TOKEN`, then run `pnpm --dir C:\Repos\shmindmaster\repocontext verify:remote`.
6. Targeted local host rollout: audit with `scripts\Sync-RepoContextHosts.ps1 -Audit`, then apply with `-Apply`. This excludes Cursor and preserves unrelated MCP registrations.
7. Remote host rollout remains pending until the production remote contract passes.

## Security

- Read-only tools only.
- No anonymous hosted repository enumeration; unauthenticated MCP requests return `401`.
- No secrets, restricted source bodies, request payloads, or bearer tokens in logs or registry files.
- The remote image is private and documentation/manifests only.

## Related source

- RepoContext repository: `C:/Repos/shmindmaster/repocontext`
- Architecture: `C:/Repos/shmindmaster/repocontext/docs/architecture.md`
