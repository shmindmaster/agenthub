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

### Configuration applied 2026-10-26 (backups `*.bak-devin-peer-20261026`)

- `%APPDATA%\devin\config.json`: interactive default `agent.model` `glm-5-2`
  (Low cost, $1.4/$4.4) -> `swe-2-medium` (Free). `/model` still picks any model per session.
- `%APPDATA%\devin\User\settings.json` (Desktop, edited while closed):
  - Devin Local preference `gemini-4-argon-medium` (High cost) -> `swe-2-medium`.
  - `devin.agentNotifications: true` (Agent Command Center notifications).
  - ACP: `factory-droid` enabled (Factory is an enabled peer). Cline is not
    registered: its ACP sessions default to a usage-billed model (Cline plan,
    cost incident).
  - Theme "AgentHub Unified - Devin Engineering": `Default Dark Modern` plus
    `workbench.colorCustomizations` for the palette (#11161D / #1B2430 / #263241,
    text #EDF2F7 / #AAB8C7, accent #35BFCB, success #4BC59A, warning #E6B35A,
    error #E87575, border #344251), matching terminal ANSI colors, Cascadia Code /
    Cascadia Mono, minimap off. App chrome outside the workbench is not themeable.
- Not set: `devin.spaces.shareContext` (values undocumented). Spaces are created
  in the Desktop UI; none were created by agents.

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
| DV-1 | A: code health | Split `qaStage` (`packages/media-studio/kit/marketing/lib/stages/qa.mjs`) into helpers behind existing tests. Taken over from Warp W-3 (Discovered, never started). | swe-2-medium | **Integrated** (run 1 20:58 stopped by the memory guard; run 2 21:01-21:15 committed `d74af67` characterization tests + `602de12` split into `qaCandidate` and nine gate helpers, max helper complexity about 11 from about 50; run 3 21:26-21:31 found the work done and re-verified 278/278 covering tests, $0). Orchestrator: full media-studio suite `node --test packages/media-studio/tests/*.test.mjs` exit 0 (172 s); independent line-by-line review found no behaviour change (gate order, awaits, SHA guards, gates.json write unchanged). Cherry-picked to main as `a294265` + `510dc04`, media-studio hash recomputed. Coverage gap: the new tests reach only the pending/prepareOnly path; the encoded-candidate chain is guarded by the review and `mvg.test.mjs` source assertions. | `C:\wt\agenthub\devin-qa-stage` (removable) | met | none |
| DV-2 | D: reliability | Read-only audit of `C:\wt` worktrees: unmerged commits, dirty files, merged-and-removable, owner. Taken over from Cline CL-4 (stalled by the memory guard). | swe-2-medium | **Verified** (run 1 stopped by the memory guard 20:36, vmware-vmx at 7.15 GB; run 2 20:53-20:58, 5.5 min, $0). Report covers 19 linked worktrees, 6 unregistered clones, 23 non-git dirs, 4 client skips. Orchestrator re-checked three claims: OC-3 `fee8a00` dangling on no branch, `cloud-render` 8 unapplied commits, `warp-parse-toml` 6/6 patch-applied: all true. | `...\devin\DV-2-report.md` | met | orchestrator pinned `fee8a00` to tgiagency `rescue/oc3-repo-standard-20261026`; owner decides cleanup of the merged-removable and non-git entries (incl. `lawli/private-beta`, 669 MB) |
| DV-3 | A/D: reconcile | Classify the 7 commits on local-ai-platform `wip/hidden-descendants-20261026` (2), `wip/scheduler-repair-main-20261026` (3), `wip/service-reservation-race-20261026` (2) against `origin/main` `ba86076` (which replaced scheduled tasks, #43): already landed / superseded / still needed, with tests. Backlog A9b (unassigned, stalled). | fusion-claude-sonnet-5-5-medium-sidekick-swe-2-medium | **Done** (21:25-21:26 CT). Devin: 6 landed (`e483df1`/`fba17b7` = main `0633152`, PR #40; `03e4ac5`=`e74a2da`, `7ff13f5`=`ce7b102` = main `8dae276`, PR #39), `f1c903d` superseded (manifest digest only); none policy-conflicting; tests not run (no pytest in the available Python). Orchestrator verified: every code file of every commit is byte-identical to `origin/main` `ba86076` ignoring CR; only the generated `manifests/source-manifest.json` differs. Branches deleted by the orchestrator on owner direction "don't leave anything pending"; tips `fba17b7d`, `f1c903d4`, `ce7b102d` | `...\devin\DV-3-report.md` | met | none (worktree `C:\wt\local-ai-platform\devin-wip-reconcile` is clean and removable) |
| DV-4 | C: browser QA | Real-Chromium QA of the saroshhussain site at 1280x800 and 375x812 on `next dev` 127.0.0.1:4311, at `origin/main` `3505733` (which carries CL-2's contact heading-order fix), so it doubles as an independent post-fix regression check of CL-2. | adaptive | **Verified** (runs 1-2 stopped by the memory guard, run 2 partly by the orchestrator's own test run; run 3 stopped itself on a real brief conflict: repo AGENTS.md requires commits on `main`, the brief named a branch; brief changed to "no commits, fixes as a patch for the orchestrator"; run 4 21:41-21:44). Result: 6 nav pages and 2 case studies (clicked from listings) load with one h1, no console errors, no 4xx/5xx; contact form keyboard-traversable, empty submit shows all 4 validation messages, no filled submit; axe 0 violations on home, case study and contact at both sizes; no 375 px overflow. One nav click flake (hydration race) re-checked as working. No defects, no patch. Orchestrator viewed the mobile contact and home screenshots and the console/network log. | `...\devin\DV-4-report.md`, `DV-4-evidence\` (26 screenshots, axe + console JSON) | met | none (worktree `C:\wt\saroshhussain\devin-browser-qa` clean at `3505733`, removable) |
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

## Batch outcome (2026-10-26, closed 21:45 CT)

All four tasks met their acceptance criteria and were verified by the
orchestrator: DV-1 integrated on agenthub `main`, DV-2 and DV-4 reports
verified, DV-3 branches retired. Models: `swe-2-medium` (Free) for DV-1/DV-2,
the Sonnet 5.5 + SWE-2 Fusion pair for DV-3 (about 1 minute), `adaptive` for
DV-4. Paid usage was small but is not measured here: `-p` runs print no
usage, and `/session-stats` is interactive only; check Settings > Usage &
limits. Lessons: memory, not the model, was the limiting factor (5 of 9 runs
were stopped or blocked before finishing); a stopped runner can leave its
dispatched Devin run going, so stop the process tree; exit 0 with empty output
happened once and must count as a failure; Devin stopped correctly on a brief
that contradicted a repository AGENTS.md.

Worktrees `devin-qa-stage`, `devin-wip-reconcile` and `devin-browser-qa` were
removed after integration.

## Owner decisions

Recorded 2026-10-26: no cloud budget (devin-cloud stays disabled); serial local
runs gated on free RAM; permissions left as they are.

Still open (none blocks Devin local dispatch):
1. A Devin Cloud budget, if cloud runs are wanted later (task, model,
   per-session `max_acu_limit`, stop condition).
2. Concurrency cap across peers (also open in the Cline plan).
3. `DEVIN_PERMISSION_MODE=dangerous` with no deny rules lets a dispatched run
   push or call `gh`; recommended `smart` plus deny rules.
4. `DEVIN_API_KEY` belongs to a different org than `DEVIN_ORG_ID`; a user PAT is
   needed to list the personal org's cloud sessions.
5. Cleanup of the `C:\wt` leftovers DV-2 classified as removable.
