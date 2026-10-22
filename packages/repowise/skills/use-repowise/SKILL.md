---
name: use-repowise
description: Use when working in any repository under C:\Repos to query the shared RepoWise workspace index (docs, symbols, history, health, cross-repo context) before broad code exploration, and to keep the index fresh after changes.
---

# Use RepoWise (fleet code intelligence)

One RepoWise workspace at `C:\Repos` (`.repowise-workspace.yaml`) covers git
repos under `C:\Repos\shmindmaster`, `C:\Repos\sh-pendoah`,
`C:\Repos\musa-dev-team`, and `C:\Repos\pendoah`. It is the derived-intelligence
layer: generated wiki docs, dependency graph, git history/ownership, code
health, dead code, decisions, and cross-repo contract links.

Per-repo indexes live in that repo's `.repowise/` directory (`wiki.db`,
`knowledge-graph.json`, `state.json`, caches). Those directories are gitignored
and must not be committed.

## Authority position

RepoWise is **derived** intelligence. Authority order in every repo:

1. Executable reality: code, tests, schemas, CI.
2. Curated knowledge: `docs/` and the repo's `AGENTS.md`.
3. RepoWise: evidence and navigation.

When they disagree, investigate and repair the stale artifact. Never cite a
RepoWise page as justification for changing intentional product or
architecture decisions.

## When to use it

- Entering an unfamiliar repo or module.
- Planning cross-cutting changes, refactors, or shared-infrastructure work.
- Assessing blast radius (risk, coupling, co-change) before touching
  high-centrality code.
- Looking for historical rationale (`repowise decision list`).
- Cross-repo questions ("which repos call this API shape?") — ask with
  `repo=all` or a specific `repo=<name>` via the workspace MCP.

Do not call it to avoid reading the exact file you are editing.

## Sibling stores

RepoWise combines repository graphs, FTS and a local vector index. Route
before you search:

| You are asking | Go to |
| --- | --- |
| Where is this symbol, who wrote it, what breaks if I change it | RepoWise (here) |
| What have we done, built, proposed, or written about X | Qdrant `knowledge`, via `use-knowledge-access` |
| Anything touching a legal matter | Qdrant `legal`, via Local-AI `query.ps1` only |

Search combines FTS5, the symbol/call graph and local vectors. The shared
server pins the OpenAI-compatible provider to `http://127.0.0.1:8790/v1`,
uses the existing `text-embedding-3-small` compatibility alias and supplies a
non-secret local placeholder key. It overrides inherited remote routing and
probes an actual finite, nonzero embedding before serving. An HTTP models
response or `embedder_degraded: false` alone does not verify vector search.
Check real search results for the vector source as well as relevance. CLI
indexing needs the same local base URL and model; preserve the existing vector
configuration. Change providers only through an explicit compatible reindex.
An empty result is unknown; try another query or `rg` and inspect the source.

The split is deliberate and should stay. A graph traversal is not a vector
query, and `legal` is walled off at the collection level so opportunity and
resume work cannot reach legal matters. Do not fold these into one store.

Scope boundary: RepoWise covers git repos under `C:\Repos`. It must never be
pointed at `D:\OneDrive - MahumTech\Documents`, which is not a git root and
carries a client-name output gate. See `docs/architecture/overview.md` in
agenthub for the full contract.

## Local-only

RepoWise on this fleet is a **local disk index**, not a hosted product.

- Indexes live in each repo's `.repowise/` (`wiki.db`, `knowledge-graph.json`,
  `state.json`). The workspace graph lives in `C:\Repos\.repowise-workspace\`.
  Those directories are gitignored.
- The agent surface is ONE shared local server, `repowise mcp C:/Repos
  --transport streamable-http --port 7339 --host 127.0.0.1`
  (`repowise-workspace`), started on demand by
  `packages/repowise/scripts/Start-RepoWiseShared.ps1`. Hosts reach it
  through the `repowise@agenthub` plugin's stdio bridge
  (`scripts/repowise_bridge.py`), which runs that launcher hidden when it
  finds 7339 down, so reconnecting the host is normally all a dead server
  needs. The launcher fails closed: it starts retrieval through
  `D:\Local-AI\ai.ps1` if the embedder (8790) is down, and exits 2 without
  starting RepoWise if the embedder still is not ready — a RepoWise started
  without it serves mock vectors for its whole life. Never register a logon
  or scheduled task for it (owner direction 2026-10-13: Task Scheduler
  `powershell.exe` opens a window and takes focus). The `repowise` CLI
  works without the server. Never bind it beyond loopback, never point
  hosts at a hosted RepoWise URL, and never add a `repowise mcp` stdio
  entry to host MCP config.
- `repowise whoami` must stay **Not signed in**. Do not `repowise login` or
  paste an `rw_live_` token. A hosted account would send repository
  intelligence off the machine.
- Telemetry must stay **disabled** (`repowise telemetry disable`). Status is
  `repowise telemetry status`.
- Default update path is `--index-only` / `--no-docs`: parse, graph, git.
  No LLM, no key.
- Hybrid search/reindex uses the local OpenAI-compatible embeddings endpoint.
  Never send repository queries or a remote credential to a hosted endpoint.
  Optional
  wiki prose (`--full` / `--docs`) still uses `REPOWISE_PROVIDER` /
  `REPOWISE_MODEL` from the process environment, never a key in AgentHub.
  Do not run `--full` against `portfolio-records` or private evidence. Do
  not `--save-key`.
- Do not add per-repo RepoWise MCP entries. Do not index
  `D:\OneDrive - MahumTech\Documents`.

## Access

CLI on this machine is uv-managed (`uv tool install repowise`). Keep it on
the PyPI latest by running `scripts/Update-RepoWise.ps1 -Apply` manually;
there is no scheduled updater. Do not install a second copy. Do not add
per-repo repowise MCP entries.

- **MCP (plugin-gated):** `repowise@agenthub` owns the entry (registry id
  `repowise-workspace`): `.mcp.json` for Claude and Cursor, `mcp.codex.json`
  for Codex. Each launches `pyw -3 scripts/repowise_bridge.py`, a small
  stdlib proxy to `http://127.0.0.1:7339/mcp` that starts the shared server
  when it is down and re-opens its session when the server restarts. If
  the handshake finds the server down it answers from the last cached
  tool list while the server starts; a call made while the launcher has
  failed closed returns an error naming the launcher log. If tools still
  fail, read `%LOCALAPPDATA%\AgentHub\runtime\repowise-shared\launcher.log`
  (exit 2 = embedder not ready; FAIL-CLOSED line says why) and
  `bridge.log` beside it, then reconnect the host or run
  `Start-RepoWiseShared.ps1` hidden. Never persist a stdio `repowise mcp`
  entry in host config or `C:/Repos/.cursor/mcp.json` — on 2026-10-02 that
  fanned out to 8 copies at ~220 MB each; the bridge is not that, it
  forwards to the one server.
  Official Claude/Codex RepoWise marketplace plugins are forbidden: they
  register a second MCP at the nearest repo instead of `C:/Repos`.
- **CLI (always available):** `repowise search "<q>"`, `repowise status -w`,
  `repowise doctor -w`, `repowise update --repo <alias>` **from `C:\Repos`**.
  Never `repowise update` from inside a member repo without `--no-agents`.
  Measured 2026-09-10: `--no-agents` still writes `.vscode/mcp.json` pointed
  at the member path. After a CLI upgrade, `repowise agents refresh
  --scope=both C:\Repos`. A member `.vscode/mcp.json` is allowed only as
  `repowise mcp C:/Repos`; `Check-RepoStandard.ps1` fails any other path.
- **Human dashboard:** `repowise serve --host 127.0.0.1 --ui-port 7338` from
  `C:\Repos`. API is `http://127.0.0.1:7337`. Port 3000 is Duckie.
- **Agent hosts:** skills + CLI everywhere; MCP only while `repowise@agenthub`
  is enabled. Distill markers in `AGENTS.md` / Cursor rules. Post-commit
  hooks on every member.

### MCP tools (call these instead of grep/read for exploration)

Core (every mode): `get_overview`, `get_answer`, `get_context`, `get_symbol`,
`search_codebase`, `get_risk`, `get_change_risk`, `get_why`, `get_dead_code`,
`get_health`. Plus `list_repos`. Workspace extras: `get_blast_radius`,
`get_architecture`. Pass `repo=<alias>` or `repo=all`.

| Situation | First call | Then |
| --- | --- | --- |
| Unfamiliar codebase | `get_overview` | `get_answer` / `get_context` |
| Any code question | `get_answer` | low confidence → `search_codebase` or `get_context` |
| Before editing a file | `get_context` | hotspot → `get_risk` |
| PR / working tree | `get_risk` with `changed_files` | read `directive` |
| Merge a commit range | `get_change_risk` | `risk_percentile` |
| Why is it shaped this way | `get_why` | — |
| Cleanup | `get_dead_code` | `safe_only=true` |

Prefer `repowise distill <cmd>` for noisy shell output; expand
`[repowise#…]` markers with `repowise expand` instead of re-running.

### When the plugin skills would have fired

There is no marketplace plugin on this fleet. Behave as those skills:

- **codebase-exploration** — how X works, where Y lives → `get_overview` / `get_answer` / `get_context`
- **pre-modification-check** — before edit/refactor/delete of unnamed shared code → `get_context` + `get_risk`
- **change-review** — PR or branch → `get_risk` / `get_change_risk` / `get_blast_radius`
- **architectural-decisions** — why / before diverging → `get_why`
- **code-health** — debt, what to refactor → `get_health`
- **dead-code-cleanup** — unused code → `get_dead_code`

## Freshness contract

- A post-commit hook in every workspace repo auto-syncs the index.
- After material changes, verify: `repowise status -w` from `C:\Repos`. If
  your repo is stale, run `repowise update --repo <alias>` (seconds).
- First-time prose docs for a repo: from inside the repo,
  `repowise update --full -y --no-workspace` (LLM spend; provider comes from
  the environment — never write keys anywhere).
- Workspace instructions live in `C:\Repos\.claude\CLAUDE.md` and
  `C:\Repos\AGENTS.md`. Per-repo managed blocks sit between `REPOWISE:START`
  markers — never hand-edit below them.

## Standard enforcement

`pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All` (in agenthub)
verifies membership, hooks, freshness, and the repository knowledge standard
across the fleet. See `docs/development/repo-standard.md` in agenthub.
