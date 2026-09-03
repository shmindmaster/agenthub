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

RepoWise is one of three retrieval stores and the only one that is not a
vector index. Route before you search:

| You are asking | Go to |
| --- | --- |
| Where is this symbol, who wrote it, what breaks if I change it | RepoWise (here) |
| What have we done, built, proposed, or written about X | Qdrant `knowledge`, via `use-knowledge-access` |
| Anything touching a legal matter | Qdrant `legal`, via Local-AI `query.ps1` only |

Search here is FTS5 keyword matching plus the symbol and call graph. An optional
embedder (`REPOWISE_EMBEDDER=gemini` on this machine) adds hybrid wiki search;
it is still not Qdrant `knowledge` or `legal`. An empty result is not evidence
the code lacks the thing — try a synonym or `grep` before concluding absence.

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
- The agent surface is local stdio: `repowise mcp C:/Repos` (`repowise-workspace`
  in `registry/mcps.json`). Do not point it at a remote URL.
- `repowise whoami` must stay **Not signed in**. Do not `repowise login` or
  paste an `rw_live_` token. A hosted account would send repository
  intelligence off the machine.
- Telemetry must stay **disabled** (`repowise telemetry disable`). Status is
  `repowise telemetry status`.
- Default update path is `--index-only` / `--no-docs`: parse files, rebuild
  the graph, refresh git/dead-code. That does not call an LLM and does not
  need an API key.
- `repowise update --full` / `--docs` is optional LLM wiki generation. It
  uses a provider from the **process environment**, never a key stored in
  AgentHub. Do not run it against `portfolio-records` or any private
  evidence repo. Do not `--save-key`.
- Do not add per-repo RepoWise MCP entries. Do not index
  `D:\OneDrive - MahumTech\Documents`.

## Access

CLI on this machine is uv-managed (`uv tool install repowise`). Keep it on
the PyPI latest with `scripts/Update-RepoWise.ps1 -Apply` (daily scheduled
task `AgentHub-Update-RepoWise`). Do not install a second copy. Do not add
per-repo repowise MCP entries.

- **MCP:** `repowise mcp C:/Repos` (stdio). Registry id `repowise-workspace`.
  After a CLI upgrade, refresh wiring with
  `repowise agents refresh --scope=both C:\Repos` (never `agents add` per
  member repo). Official Claude/Codex marketplace plugins are not installed:
  they would register a second MCP at the nearest repo instead of `C:/Repos`.
- **CLI:** `repowise search "<q>"`, `repowise status -w`,
  `repowise doctor -w`, `repowise update --repo <alias>` from `C:\Repos`.
- **Human dashboard:** `repowise serve --host 127.0.0.1 --ui-port 7338` from
  `C:\Repos`. API is `http://127.0.0.1:7337`. Port 3000 is Duckie.
- **Agent hosts wired at the workspace:** Claude Code, Claude Desktop, Codex
  (hooks + 18 prompts), Cursor (`.cursor/mcp.json` + rules), VS Code, OpenCode,
  Hermes. Distill markers in `AGENTS.md` / Cursor rules. Post-commit hooks on
  every member.

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
