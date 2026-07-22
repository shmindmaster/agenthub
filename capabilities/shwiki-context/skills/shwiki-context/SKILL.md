---
name: shwiki-context
description: Code-first portfolio context via the local ShWiki index. Use for cross-repository catalog, search, provenance, freshness, comparisons, documentation gaps, and commit-pinned source evidence. Eight read-only MCP tools only.
---

# ShWiki context skill

## When to use

Use this skill for portfolio documentation and code context across ShMindMaster, Pendoah, and Sabhi repositories. It is especially useful for cross-repository discovery, source provenance, freshness, documentation gaps, and bounded code evidence.

ShWiki is a repository-derived context layer, not an authority above current code and not authorization to change a repository or runtime.

## Source precedence

1. Current source code in the target checkout
2. Tests, manifests, CI, and deployment configuration
3. Git history and current branch state
4. Commit-pinned ShWiki code evidence
5. Generated or imported wiki documentation
6. Manually written prose

## Required workflow

1. Identify the current checkout, GitHub owner/account, branch, and commit.
2. Inspect current code and tests before relying on prose.
3. Use ShWiki for bounded cross-repository context and provenance.
4. Cite repository, source path, and commit SHA when answering from ShWiki evidence.
5. Report freshness and confidence when returned by the tool.
6. Prefer local ShWiki on this workstation because its hourly index covers the approved local clones.
7. Use the hosted endpoint only when local stdio is unavailable or a reviewed hosted snapshot is specifically required.
8. Never treat ShWiki output as permission to edit, deploy, merge, rotate credentials, or access restricted data.

## MCP contract

Canonical server name: `shwiki-context`.

| Priority | Transport | How |
| --- | --- | --- |
| Primary | Local stdio | `pnpm --dir C:/Repos/shmindmaster/shwiki mcp:wiki` |
| Fallback | Remote HTTP | `https://shwiki.shtrial.com/api/mcp` with host-managed auth |

The MCP surface is exactly eight read-only, job-oriented tools:

| Tool | Job |
| --- | --- |
| `wiki.catalog` | List repositories or inspect sync and stale-page signals (`view`: `repositories`, `sync`, or `stale`) |
| `wiki.search` | Search bounded documentation results, optionally within one repository |
| `wiki.get` | Read one page together with its commit and source trace |
| `wiki.analyze` | Report documentation gaps or compare repository coverage |
| `repo.inspect` | Inspect `status`, `commit`, `manifest`, `ci`, `tests`, `changes`, `trace`, or `drift` |
| `repo.read` | Read a safe commit-pinned source-file slice |
| `repo.search` | Search safe source code with bounded evidence |
| `repo.compare` | Compare safe changed paths between two commits |

There are no MCP proposal or mutation tools. Documentation changes use the normal authorized repository workflow, outside ShWiki MCP.

## Safe call examples

- Catalog: `wiki.catalog` with `{ "view": "repositories" }`
- Repository status: `repo.inspect` with `{ "repository": "lawli", "operation": "status" }`
- Local Pendoah status: `repo.inspect` with `{ "repository": "tellgence-backend", "operation": "status" }`
- Page lookup: `wiki.get` with `{ "repository": "lawli", "sourcePath": "docs/00-overview.md" }`

## Index freshness

The Windows task **ShWiki Local Index** refreshes the approved local registry hourly. It fast-forwards only the registered branch when tracked files are clean and there are no local-only commits. Wrong-branch, dirty, ahead, diverged, or unreachable checkouts are preserved and reported. It never commits or pushes.

Run `pnpm --dir C:/Repos/shmindmaster/shwiki index:local` only when the user explicitly asks for an immediate refresh or the task requires current indexing evidence.

## Evidence and safety rules

- Prefer `direct-source` confidence and commit-pinned evidence.
- Treat stale or snapshot evidence as navigation until confirmed in the checkout.
- Never embed secrets, legal originals, customer, patient, or production financial data in prompts, logs, or commits.
- Register one server named `shwiki-context`; do not create duplicate ShWiki implementations.
- Store remote tokens only in host secret stores. Local stdio requires no ShWiki token.
- Mark a host configured only after its native list/doctor succeeds and both safe example calls work.
