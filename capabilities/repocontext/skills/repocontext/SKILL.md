---
name: repocontext
description: Code-first private portfolio context via RepoContext. Use for cross-repository catalog, search, provenance, comparisons, documentation gaps, and commit-pinned source evidence. Eight read-only MCP tools only.
---

# RepoContext skill

## When to use

Use this skill for portfolio documentation and code context across ShMindMaster, Pendoah, and Sabhi repositories. It is especially useful for cross-repository discovery, source provenance, freshness, documentation gaps, and bounded code evidence.

RepoContext is a repository-derived context layer, not an authority above current code and not authorization to change a repository or runtime.

## Source precedence

1. Current source code in the target checkout
2. Tests, manifests, CI, and deployment configuration
3. Git history and current branch state
4. Commit-pinned RepoContext code evidence
5. Indexed repository documentation
6. Manually written prose

## Required workflow

1. Identify the current checkout, GitHub owner/account, branch, and commit.
2. Inspect current code and tests before relying on prose.
3. Use RepoContext for bounded cross-repository context and provenance.
4. Cite repository, source path, and commit SHA when answering from RepoContext evidence.
5. Report freshness and confidence when returned by the tool.
6. Use local stdio while remote deployment is pending or whenever full commit-pinned code search is required.
7. Use the hosted endpoint only after its authenticated production contract has passed; it contains a narrower documentation/manifests snapshot.
8. Never treat RepoContext output as permission to edit, deploy, merge, rotate credentials, or access restricted data.

## MCP contract

Canonical server name: `repocontext`.

| Priority | Transport | How |
| --- | --- | --- |
| Validated local | stdio | `pnpm --dir C:/Repos/shmindmaster/repocontext mcp:serve` |
| Private remote, after production verification | Streamable HTTP | `https://repocontext.shtrial.com/api/mcp` with `REPOCONTEXT_MCP_TOKEN` |

The MCP surface is exactly eight read-only, job-oriented tools:

| Tool | Job |
| --- | --- |
| `wiki.catalog` | List repositories or inspect sync and stale-page signals (`view`: `repositories`, `sync`, or `stale`) |
| `wiki.search` | Search bounded documentation results, optionally within one repository |
| `wiki.get` | Read one page together with its commit and source trace |
| `wiki.analyze` | Report documentation gaps or compare repository coverage |
| `repo.inspect` | Inspect `status`, `commits`, `manifest`, `tests`, or `changes` |
| `repo.read` | Read a safe commit-pinned source-file slice |
| `repo.search` | Search safe source code with bounded evidence |
| `repo.compare` | Compare safe changed paths between two commits |

There are no MCP proposal or mutation tools. Documentation changes use the normal authorized repository workflow, outside RepoContext.

## Safe call examples

- Catalog: `wiki.catalog` with `{ "view": "repositories" }`
- Repository status: `repo.inspect` with `{ "repository": "lawli", "operation": "status" }`
- CrewScore status: `repo.inspect` with `{ "repository": "crewscore", "operation": "status" }`
- Page lookup: `wiki.get` with `{ "repository": "lawli", "sourcePath": "docs/00-overview.md" }`

## Index boundary

- The registry contains Git repositories only.
- Local reads and searches use bytes committed at the current `HEAD`; dirty and untracked work is excluded.
- The private remote snapshot includes committed documentation, selected root manifests, and workflow metadata only.
- Snapshot files flagged by gitleaks are excluded and recorded in the local build report.

## Evidence and safety rules

- Prefer `direct-source` confidence and commit-pinned evidence.
- Treat stale or snapshot evidence as navigation until confirmed in the checkout.
- Never embed secrets, legal originals, customer, patient, or production financial data in prompts, logs, or commits.
- Register one server named `repocontext`; map retired aliases (`shwiki`, `shwiki-context`, `shwiki-context-remote`, `sh-knowledge`) to it during migration.
- Store `REPOCONTEXT_MCP_TOKEN` only in host secret stores. Local stdio requires no token.
- Mark a host configured only after its native list/doctor succeeds and both safe example calls work.
