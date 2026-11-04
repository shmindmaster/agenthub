---
name: repowise
description: Use when exploring or changing code in a repository under C:/Repos on a host that uses the AgentHub RepoWise bridge, to query the shared workspace index (symbols, history, health, risk, cross-repo links) before broad searching, and to refresh that index. Claude and Codex use the vendor plugins instead.
---

# RepoWise

One workspace at `C:/Repos` indexes every repo under it. Per-repo indexes live in `.repowise/` (gitignored, never committed). Code, tests, schemas and CI outrank curated docs, and both outrank RepoWise; when they disagree, fix the stale artifact. An empty result means unknown: try another query or `rg`.

## Query

Read the exact file you are editing; use the index for orientation and impact.

| Situation | First | Then |
| --- | --- | --- |
| Unfamiliar repo | `get_overview` | `get_answer`, `get_context` |
| Code question | `get_answer` | low confidence: `search_codebase`, `get_context` |
| Before editing | `get_context` | hotspot: `get_risk` |
| Working tree or PR | `get_risk` with `changed_files` | read `directive` |
| Commit range | `get_change_risk` | `risk_percentile` |
| Why it is shaped this way | `get_why` | |
| Cleanup | `get_dead_code` with `safe_only=true` | |

Pass `repo=<alias>` or `repo=all`. Wrap noisy commands in `repowise distill <cmd>`; recover omitted output with `repowise expand`.

## Hosts

- Claude uses vendor `repowise@repowise`, Codex uses vendor `codex@repowise` (both from `repowise-dev/repowise`). They own MCP, hooks and skills. Uninstall `repowise@agenthub` there and never re-enable it. Never register both routes on one host.
- Other hosts use the AgentHub bridge to one shared loopback server (port 7339), started by `Start-RepoWiseShared.ps1`. It fails closed when the embedder probe fails, with no local embedding fallback.
- Add no per-repository MCP entries, user hooks, post-commit hooks, logon tasks or scheduled updaters.

## Rules

- `repowise whoami` stays "Not signed in". Never run `repowise login`, use an `rw_live_` token, or `--save-key`.
- Telemetry stays disabled (`repowise telemetry status`).
- Never run bare `repowise update`, `repowise agents refresh`, `--full`, docs generation or first-time init.
- Never index `D:/OneDrive - MahumTech/Documents`, and never run `--full` against private evidence.
- Embeddings use MahumTech Azure OpenAI `mt-foundary-resource`, deployment `text-embedding-3-small`, read from env and never persisted. Never read `AZURE_OPENAI_*` or any `pndh` host. Setup and probe details: `references/setup.md`.

## Refresh the index

After material changes, refresh only through `packages/repowise/scripts/Invoke-RepoWiseBoundedIndex.ps1`: one repo, index-only, memory-capped, deadline-bound. Read `references/refresh.md` for its parameters and acceptance checks before running it.

Report the receipt result and real retrieval quality (run actual queries) separately; a clean receipt does not prove vector search works.

## References

- `references/setup.md`: read when configuring embeddings, the CLI, the dashboard or hosted mode.
- `references/refresh.md`: read when running the bounded refresh or reviewing Codex vendor hooks.
