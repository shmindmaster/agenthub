---
name: repowise
description: Answers code questions from the shared RepoWise workspace index (symbols, history, health, risk, cross-repo links) and refreshes it. Use when exploring or changing code under C:/Repos on a host using the AgentHub bridge; Claude and Codex use the vendor plugins.
---

# RepoWise

## Workflow contract

1. Resolve the repository and revision, then pick symbol, history or risk evidence for the question.
2. Read the cited source at the intended revision. Check index freshness and use the bounded refresh only when needed and allowed.
3. Return repository, revision, source locations and retrieval mode. Report stale or degraded retrieval explicitly.
4. If the refresh lease is held or the index is stale, verify with live source and report the bounded refresh result separately.

One workspace at `C:/Repos` indexes every repo under it. Per-repo indexes live in `.repowise/` (gitignored, never committed). Code, tests, schemas and CI outrank curated docs, and both outrank RepoWise; when they disagree, fix the stale artifact. An empty result means unknown: try another query or `rg`.

## Hosts

- Claude uses vendor `repowise@repowise`, Codex uses vendor `codex@repowise` (both from `repowise-dev/repowise`). They own hooks and skills, and `Install-RepoWiseVendorLauncher.ps1` points their MCP entry at the bridge below. Uninstall `ah-repowise@agenthub` there and never re-enable it. Never register both routes on one host.
- Every host reaches one shared loopback server (port 7339) through the AgentHub bridge. The bridge starts it on demand through `Start-RepoWiseShared.ps1`, it exits after 30 idle minutes, and calls that name no repo go to the repo the session started in. It fails closed when the embedder probe fails, with no local embedding fallback.
- Add no per-repository MCP entries, user hooks, post-commit hooks, logon tasks or scheduled updaters.

## Rules

- `repowise whoami` stays "Not signed in". Never run `repowise login`, use an `rw_live_` token, or `--save-key`.
- Telemetry stays disabled (`repowise telemetry status`).
- Never run bare `repowise update`, `repowise agents refresh`, `--full`, docs generation or first-time init.
- Never index `D:/OneDrive - MahumTech/Documents`, and never run `--full` against private evidence.
- Embeddings use MahumTech Azure OpenAI `mt-foundary-resource`, deployment `text-embedding-3-small`, read from env and never persisted. The `AZURE_OPENAI_*` and `FOUNDRY_*` variables are valid only while their endpoint host is `mt-foundary-resource`; never use `AZURE_OPENAI_PNDH_*` or any `pndh` host. Setup and probe details: `references/setup.md`.

## Refresh the index

Refresh with `pwsh -NoProfile -File <agenthub>/packages/repowise/scripts/Invoke-RepoWiseRefreshChanged.ps1`. It visits only entries whose files moved, one at a time, and at most once in 20 hours. For one repo use `Invoke-RepoWiseBoundedIndex.ps1`. Read `references/refresh.md` for parameters and acceptance checks before running either.

Report the receipt result and real retrieval quality (run actual queries) separately; a clean receipt does not prove vector search works.

## References

- `references/setup.md`: read when configuring embeddings, the CLI, the dashboard or hosted mode.
- `references/refresh.md`: read when running the bounded refresh or reviewing Codex vendor hooks.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
