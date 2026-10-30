---
name: use-repowise
description: Use when working in any repository under C:\Repos to query the shared RepoWise workspace index (docs, symbols, history, health, cross-repo context) before broad code exploration, and to keep the index fresh after changes.
---

# Use RepoWise (fleet code intelligence)

One workspace at `C:\Repos` (`.repowise-workspace.yaml`) covers `C:\Repos\shmindmaster`, `C:\Repos\sh-pendoah`, `C:\Repos\musa-dev-team`, `C:\Repos\pendoah`. Provides wiki docs, dependency graph, git history/ownership, code health, dead code, decisions, cross-repo contract links. Per-repo indexes in `.repowise/` (`wiki.db`, `knowledge-graph.json`, `state.json`, caches); gitignored, never committed.

## 1. Authority

1. Executable reality: code, tests, schemas, CI.
2. Curated knowledge: `docs/` and `AGENTS.md`.
3. RepoWise: evidence and navigation.

When they disagree, repair the stale artifact. Never cite RepoWise to justify changing intentional product/architecture decisions.

## 2. When to use

Unfamiliar repo/module entry, cross-cutting changes, blast-radius assessment, historical rationale (`repowise decision list`), cross-repo questions (`repo=all` or `repo=<name>`). Do not call it to avoid reading the exact file being edited.

## 3. Sibling stores

| Question | Store |
|---|---|
| Symbol location, authorship, change impact | RepoWise |
| What we've done/built/proposed about X | Qdrant `knowledge` via `use-knowledge-access` (local or hosted, whichever the overlay selects; the hosted store holds only register-cleared sources) |
| Legal matters | Qdrant `legal` via Local-AI `query.ps1` only |

Embeddings: MahumTech Azure OpenAI `aoai-mrender-4e123a95`, deployment `text-embedding-3-small` (1536-d), via RepoWise's `openai` embedder. Read from env at start, never persisted: `FOUNDRY_OPENAI_BASE_URL` (`https://aoai-mrender-4e123a95.openai.azure.com/openai/v1/`), `FOUNDRY_API_KEY` or `AZURE_AI_SERVICES_KEY`, `FOUNDRY_EMBEDDING_DEPLOYMENT`. Never read `AZURE_OPENAI_*` (client account) or any `pndh` host; https and `*.openai.azure.com` only. Probe must return finite nonzero embedding before serving; HTTP models response or `embedder_degraded: false` alone insufficient—check real search results for vector source and relevance. CLI indexing and updates need the same base URL, key, deployment and width (see the refresh one-liner below); preserve existing vector config. Azure Batch does not cover embedding models and the real-time deployment allows 100K TPM, so full re-embeds are throttled and slow. Change providers only through explicit compatible reindex. Empty result is unknown; try another query or `rg`. Do not fold stores; `legal` walled at collection level.

**Scope boundary:** Never point at `D:\OneDrive - MahumTech\Documents` (not git root, client-name output gate). See `docs/architecture/overview.md` in agenthub.

## 4. Local-only constraints

These apply in the default **local** mode. Section 4a covers the hosted mode.

- Workspace graph in `C:\Repos\.repowise-workspace\`.
- ONE shared server: `repowise mcp C:/Repos --transport streamable-http --port 7339 --host 127.0.0.1` (`repowise-workspace`), started by `packages/repowise/scripts/Start-RepoWiseShared.ps1`. Hosts reach via `repowise@agenthub` stdio bridge (`scripts/repowise_bridge.py`), launches hidden when 7339 down. Launcher fails closed: runs `shared_server.py --check-embedder` (one real Azure probe embedding) and exits 2 with `FAIL-CLOSED` when the Azure env is missing or the probe fails; it starts no local embedder. Never register logon/scheduled task (owner 2026-10-13: Task Scheduler `powershell.exe` opens window, takes focus). Never bind beyond loopback, never point the local server or a host config at a hosted URL (hosted access goes only through the bridge remote mode in 4a), never add `repowise mcp` stdio entry to host config.
- `repowise whoami` must stay **Not signed in**. No `repowise login`, no `rw_live_` token.
- Telemetry **disabled** (`repowise telemetry disable`; check `repowise telemetry status`).
- Default update: `--index-only`/`--no-docs` (parse, graph, git; no LLM/key).
- Optional wiki prose (`--full`/`--docs`) uses `REPOWISE_PROVIDER`/`REPOWISE_MODEL` from environment, never key in AgentHub. Never `--full` against `portfolio-records` or private evidence. No `--save-key`.
- No per-repo MCP entries. No indexing `D:\OneDrive`.

## 4a. Hosted mode (bridge remote mode)

The same `repowise@agenthub` bridge can forward to a self-hosted RepoWise endpoint instead of the local shared server. It is off by default and owned by the private overlay, which sets the switch, URL and token outside this repository:

| Variable | Meaning |
|---|---|
| `AGENTHUB_REPOWISE_MODE` | `local` (default) or `remote` |
| `AGENTHUB_REPOWISE_REMOTE_URL` | hosted MCP URL, https only |
| `AGENTHUB_REPOWISE_REMOTE_TOKEN_ENV` | name of the env var that holds the bearer token (default `REPOWISE_REMOTE_TOKEN`) |

- In remote mode the bridge never starts the local launcher and never falls back to local: an unreachable remote, a missing token or a refused token returns a JSON-RPC error naming the cause. Switch back with `AGENTHUB_REPOWISE_MODE=local` and restart the host session.
- The handshake cache is per mode (`bridge-cache.json` / `bridge-cache-remote.json`). The token is never logged or echoed.
- The hosted index only contains repositories its owner has cleared for off-machine hosting. A repo missing from `list_repos` in remote mode is a scope decision, not an indexing fault: use local mode or `rg` for it.
- Still forbidden in either mode: `repowise login`, `rw_live_` tokens, hosted RepoWise accounts, persisting a remote URL or token in any tracked file or host config.

## 5. Access

CLI uv-managed (`uv tool install repowise`). Update via `scripts/Update-RepoWise.ps1 -Apply` manually; no scheduled updater; no second copy.

- **MCP (plugin-gated):** `repowise@agenthub` (registry `repowise-workspace`): `.mcp.json` for Claude/Cursor, `mcp.codex.json` for Codex. Each launches `pyw -3 scripts/repowise_bridge.py` (stdlib proxy to `http://127.0.0.1:7339/mcp`; starts server when down, re-opens session on restart). Handshake with server down answers from cached tool list; calls during fail-closed return error naming launcher log. If tools still fail, reconnect the host or run `Start-RepoWiseShared.ps1` hidden after checking logs. On failure read `%LOCALAPPDATA%\AgentHub\runtime\repowise-shared\launcher.log` (exit 2 = Azure embedder env missing or probe failed) and `bridge.log`. Never persist stdio `repowise mcp` in host config or `C:/Repos/.cursor/mcp.json` (2026-10-02: 8 copies ~220 MB each). Marketplace plugins forbidden (register second MCP at nearest repo).
- **CLI:** `repowise search "<q>"`, `repowise status -w`, `repowise doctor -w` from `C:\Repos`. Never bare `repowise update` from member repo. `--no-agents` unsafe: 0.58.0 persists (CLI is now 0.59.0; bridge, bounded-index and updater tests pass on it, and this behavior is not re-verified) `editor_files.agents_md: false` into `.repowise/config.yaml`; earlier CLI wrote `.vscode/mcp.json` at member path. After upgrade: `repowise agents refresh --scope=both C:\Repos`. Manual incremental refresh, workspace-wide (changed files only; no `watch`, no git hooks, no schedule): `$env:OPENAI_API_KEY=$env:FOUNDRY_API_KEY; $env:OPENAI_BASE_URL=$env:FOUNDRY_OPENAI_BASE_URL; $env:REPOWISE_EMBEDDER='openai'; $env:REPOWISE_EMBEDDING_MODEL=$env:FOUNDRY_EMBEDDING_DEPLOYMENT; repowise update --workspace C:\Repos`. Member `.vscode/mcp.json` allowed only as `repowise mcp C:/Repos`; `Check-RepoStandard.ps1` fails others.
- **Dashboard:** `repowise serve --host 127.0.0.1 --ui-port 7338` from `C:\Repos`. API `http://127.0.0.1:7337`. Port 3000 is Duckie.
- **Agent hosts:** skills + CLI everywhere; MCP only while `repowise@agenthub` enabled. No unbounded post-commit hooks.
- Workspace instructions: `C:\Repos\.claude\CLAUDE.md`, `C:\Repos\AGENTS.md`. Managed blocks between `REPOWISE:START` markers—never hand-edit below.

### MCP tools

Core: `get_overview`, `get_answer`, `get_context`, `get_symbol`, `search_codebase`, `get_risk`, `get_change_risk`, `get_why`, `get_dead_code`, `get_health`, `list_repos`. Workspace: `get_blast_radius`, `get_architecture`. Pass `repo=<alias>` or `repo=all`.

| Situation | First | Then |
|---|---|---|
| Unfamiliar codebase | `get_overview` | `get_answer`/`get_context` |
| Code question | `get_answer` | low confidence → `search_codebase`/`get_context` |
| Before editing | `get_context` | hotspot → `get_risk` |
| PR/working tree | `get_risk` + `changed_files` | read `directive` |
| Merge range | `get_change_risk` | `risk_percentile` |
| Why shaped this way | `get_why` | — |
| Cleanup | `get_dead_code` | `safe_only=true` |

Prefer `repowise distill <cmd>` for noisy output; expand `[repowise#…]` with `repowise expand`.

## 6. Bounded manual freshness

After material changes run `scripts/Invoke-RepoWiseBoundedIndex.ps1` with absolute `-Workspace`, `-RepositoryRoot`, `-LeasePath`, `-OutputDirectory`, timezone-bearing `-Deadline`. Use shared heavy-work lease path; foreign lease is refusal.

One repo, index-only, no agent generation, Windows Job Object before child. Defaults: 8 GiB aggregate commit-memory ceiling, 900 s, strictly >8 GiB free physical RAM. Free RAM below floor stops only owned job. Deadline shortens budget. Owner may waive free-RAM floor via `-RamFloorWaiverReason` (1–512 nonblank chars); waives only admission/runtime free-RAM checks—memory cap, timeout, deadline, lease, local-provider and source fences remain. Lease/receipt record waiver; never infer/reuse for another task. Follow closed heavy-work window; do not start in it. No service started/stopped, no scheduled work.

Child uses the shared server's Azure embedding probe (same deployment and width). Receipts/logs must resolve (junctions/symlinks followed) beneath `%LOCALAPPDATA%\AgentHub`, outside source workspace; other `-OutputDirectory` refused, no receipt. Python hidden via `System.Diagnostics.Process`, never call operator. 0.58.0 `update` regenerates `.claude/CLAUDE.md` unless `.repowise/config.yaml` sets `editor_files.claude_md: false`, regenerates AGENTS.md when `editor_files.agents_md` true, no per-run switch. Wrapper refuses unless opt-out already configured (never writes config); creating it is owner decision per repo. Submodule fenced by gitlink commit and checked-out HEAD.

Acceptance: exit zero, no owned descendants, exact HEAD in `state.last_sync_commit`, unchanged HEAD/staged/tracked/nonignored source and known agent config. Unexpected source edit fails; never silently reverted. Source fence: Git-visible files plus `.vscode/mcp.json`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md`, `.repowise/config.yaml`.

Wrapper removes lease only when no owned processes remain. Exit 3: lease stays, operator verifies before removing. Wrapper killed → job terminated with it. Incremental only—not provider migration or full rebuild. Receipt does not prove vector retrieval quality; check real queries separately.

No automatic post-commit refresh. No unbounded update, `--full`, docs generation, or first-time init through this wrapper.

## 7. Standard enforcement

`pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All` (in agenthub) verifies membership, hooks, freshness, repository knowledge standard. See `docs/development/repo-standard.md` in agenthub.
## 8. Final check

- [ ] Source verified any derived claims used for decisions.
- [ ] Local routing, telemetry, workspace and privacy boundaries preserved.
- [ ] Refresh used bounded entry point with task-specific lease and deadline.
- [ ] Receipt acceptance and real retrieval quality reported separately.

Existing index required. Hybrid search/reindex uses local OpenAI-compatible embeddings. Never send repository queries or a remote credential to a hosted endpoint.
