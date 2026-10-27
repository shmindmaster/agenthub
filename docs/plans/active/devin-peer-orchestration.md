# Devin peer orchestration

Started 2026-10-26 by the Claude "Devin Planner / Orchestrator" session, on the
owner's request to make Devin (CLI, Desktop, Cloud) a first-class execution
peer. This file is the Devin task registry, routing policy and runbook. It is a
sibling of `opencode-peer-orchestration.md` (cross-agent backlog A1-A16,
OC-1..OC-5, F-1..F-4), `cline-peer-orchestration.md` and
`warp-peer-orchestration.md`; it does not duplicate their rows. Runtime
evidence: `%LOCALAPPDATA%\AgentHub\runtime\orchestration\2026-10-26\devin\`.

## Owner direction (2026-10-26, this session)

- Admit Devin as a peer, local and cloud. **No cloud budget for this batch**, so
  `dispatchPolicy.devin-cloud` stays disabled; only local runs are enabled.
- Local Devin tasks run **one at a time, only once free RAM is above 6 GB**; a
  run is stopped if free RAM falls below 1.5 GB.
- **Permissions stay as they are**: user env `DEVIN_PERMISSION_MODE=dangerous`
  and `launchDefaults.devin`. No deny rules were added.
- Supersedes, for Devin local runs only, 2026-10-23 20:21 CT ("only Cursor, Grok
  and Codex may run agent work"). The 2026-10-15 one-host rule still applies:
  at 20:15 CT Codex (4), Cline (3), Factory, Grok (2) and OpenCode were running,
  free RAM was 1.2 GB and CPU 100%.

## Verified state (2026-10-26)

| Surface | State | Evidence |
|---|---|---|
| Devin CLI | 3000.11.205, logged in, Devin Pro, team approved | `devin auth status`, `devin doctor` 3/3 |
| Config | `%APPDATA%\devin\config.json`: model `glm-5-2`, `read_config_from` = `agents_standard` only (claude, cursor, windsurf, copilot, opencode, zed false) | read 2026-10-26 |
| Instructions | `%APPDATA%\devin\AGENTS.md` (AgentHub-managed) | Sync-AgentHub audit: `[devin] mcp=unchanged` |
| Skills | 111 via `%APPDATA%\devin\skills` -> junction to `~\.agents\skills` | `devin skills` |
| MCP | 12 servers in `%APPDATA%\devin\mcp_config.json` (11 remote, brave-search stdio) | `devin mcp list` |
| Subagents / hooks | none (AgentHub generates no Devin subagents; hooks deliberately null) | `subagent-formats.json`, `agents.json` |
| Sandbox | **unsupported on Windows**; `autonomous` mode needs it | docs.devin.ai/cli/sandbox |
| Devin Desktop | 3.11.216 (VS Code 1.126 base) installed, not running; no extensions; ACP agents enabled in settings: github-copilot-cli, gemini, claude-acp, codex-acp, devin-cloud, opencode-v2 | `%APPDATA%\devin\User\settings.json` |
| Devin Cloud | disabled. The user-scope `DEVIN_API_KEY` is a service-user key ("SHMain") in an org that differs from `DEVIN_ORG_ID`; it lists 0 sessions in its own org and gets 403 on the `DEVIN_ORG_ID` org | `GET /v3/self`, `/v3/organizations/{org}/sessions` |
| Local history | 2 IDE sessions (`backend_type windsurf`): "Open a Browser Preview of the Website" (duckie-app), "Clean Up Old Sessions and Fix Amp Agent PATH Error" | `cli\sessions.db` (read-only) |
| Stale config | `~\.config\devin\config.json` (2026-08-04) lists MCP servers the CLI no longer reads | not changed |

Gaps not established: Devin Desktop ACP registry file (none found under
`%APPDATA%\devin`; docs name `%USERPROFILE%\AppData\Roaming\Code\User\acp\registry.json`),
Local Hands on Windows, Pro spend caps, Fusion eligibility on Pro (docs say
"paid plans"; Pro is not named).

## Models and routing

`devin models list --format json` (816 variants). Allowlist in
`dispatchPolicy.devin.allowedModels`; the dispatcher refuses anything else.

| Model | Cost | Use for |
|---|---|---|
| `swe-2-medium` (default) | Free | reconnaissance, audits, routine refactors behind tests |
| `swe-2-high`, `swe-2-max` | Free | harder implementation and debugging |
| `adaptive` | $0.5 / $0.1 / $2 per 1M in / cached / out | tool-heavy or browser work where routing helps |
| `fusion-claude-sonnet-5-5-medium-sidekick-swe-2-medium` | lead $2 / $0.1 / $10, sidekick Free | correctness-critical review and design |

Excluded: `swe-2-medium-lightning` (the former default, High cost $1/$5),
Opus/Fable/GPT Fusion leads. Paid models draw the Pro daily/weekly quota, then
on-demand credits. Check Settings > Usage & limits for auto-reload before any
paid run; `/session-stats` shows per-session cost interactively.

Rules: start free; escalate one tier after a demonstrated failure; review with
a different model family than the implementer.

## Task registry

Lifecycle: Discovered -> Prioritized -> Assigned -> Running -> Review ->
Verified -> Integrated -> Done (plus Blocked / Stalled / Failed / Superseded).

| ID | Workstream | Objective | Model | Status | Location | Acceptance | Next action |
|---|---|---|---|---|---|---|---|
| DV-1 | A: code health | Split `qaStage` (`packages/media-studio/kit/marketing/lib/stages/qa.mjs`) into helpers behind existing tests. Taken over from Warp W-3 (Discovered, never started). | swe-2-medium | Assigned | `C:\wt\agenthub\devin-qa-stage` | media-studio tests pass; behaviour unchanged; local commit; report | start when RAM allows |
| DV-2 | D: reliability | Read-only audit of `C:\wt` worktrees: unmerged commits, dirty files, merged-and-removable, owner. Taken over from Cline CL-4 (stalled by the memory guard). | swe-2-medium | Assigned | `...\devin\DV-2-work` (report only) | every `C:\wt` repo listed with evidence; nothing changed | start when RAM allows |
| DV-3 | A/D: reconcile | Classify the 7 commits on local-ai-platform `wip/hidden-descendants-20261026` (2), `wip/scheduler-repair-main-20261026` (3), `wip/service-reservation-race-20261026` (2) against `origin/main` `ba86076` (which replaced scheduled tasks, #43): already landed / superseded / still needed, with tests. Backlog A9b (unassigned, stalled). | fusion-claude-sonnet-5-5-medium-sidekick-swe-2-medium | Assigned | `C:\wt\local-ai-platform\devin-wip-reconcile` (read-only) | each commit classified with file:line evidence; tests run; no branch changes | start when RAM allows |
| DV-4 | C: browser QA | Real browser workflow with evidence (screenshots, console) on a local dev server. CL-2 (Cline, saroshhussain site) is stalled; reassign only after its owner releases it. | adaptive | Discovered | — | interactions, expected/actual, screenshots, console log | owner: release CL-2 to Devin or name another app |
| X-81 | review follow-up | agenthub#81 review findings (OC-4) after merge | — | Verified (orchestrator) | `main` `cfebd89` | F-01 `validate-sync.mjs:272` passes `allowAsrAnchored`; F-02 `picture-gates.mjs:127` returns not-ok on `report.ok === false`; no `key=` in `cloud-ai.mjs`; `cloud-render.mjs:388-395` stops siblings on failure; `cloud-ai.mjs:182-214` never spills to another paid provider | none |

## Runbook

- **Interactive CLI:** `devin` in a repo (or a `C:\wt` worktree). `/model` to
  choose (prefer `swe-2-medium`), `/fusion` for a lead/sidekick pair (CLI only;
  Desktop uses its model picker), `/plan`, `/ask`, `/session-stats`, `/compact`.
  Resume: `devin -c` (last) or `devin -r` (picker). `devin list` is an
  interactive picker, not a plain list.
- **Desktop:** `devin-desktop .` (or `devin desktop`). Agent Command Center shows
  local and cloud sessions; notifications need `devin.agentNotifications`.
  Desktop is an Electron IDE: do not open it while other hosts saturate RAM.
- **Dispatch a task:** write a brief, create a worktree with
  `New-AgentHubWorktree.ps1`, then
  `pwsh -NoProfile -File <agenthub>\packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1 -HostId devin -PromptFile <brief> -Cwd <worktree> -Model swe-2-medium -TimeoutSec 3600`.
  Output lands in `%LOCALAPPDATA%\AgentHub\runtime\coding-agent-dispatch\`.
- **Take over manually:** stop the dispatched process, then `devin -c` in the
  same worktree.
- **Review and integrate:** read the task report, diff the branch, rerun the
  tests yourself. Push/PR only with owner approval.
- **No monitoring daemon** by policy. A batch runner is a bounded foreground
  job of the orchestrator session and stops before 01:00 CT.
- **This batch:** `D:\AgentHub\runtime\orchestration\2026-10-26\devin\Start-DevinBatch.ps1`
  runs DV-0 (one-line smoke on `swe-2-medium`, aborts the batch unless it returns
  READY), then DV-2, DV-1, DV-3 in order. It waits for free RAM >= 6 GB before each
  start, kills the run's process tree below 1.5 GB, starts nothing after 00:30 and
  stops everything at 01:00. Events: `DV-batch.events.jsonl`; per-task output:
  `DV-n.dispatch.log`; reports: `DV-n-report.md`. Restart a subset with
  `-Only DV-1,DV-3`.

## Open owner decisions

1. Devin Cloud budget (task, model, per-session `max_acu_limit`, stop condition).
2. Concurrency cap across peers (also open in the Cline plan).
3. `DEVIN_PERMISSION_MODE=dangerous` with no deny rules: any dispatched run can
   push or call `gh`. Recommended: `smart` plus deny rules in `%APPDATA%\devin\config.json`.
4. `DEVIN_API_KEY` org differs from `DEVIN_ORG_ID`; a user PAT is needed to list
   the personal org's cloud sessions.
5. DV-4 target app.
