# Cline peer orchestration

Started 2026-10-26 by the Claude "Cline Planner / Orchestrator" session, on the
owner's request to make Cline a first-class execution peer and delegate 3-4
substantial tasks to it. This file is the Cline task registry, routing policy
and runbook. It is the sibling of `opencode-peer-orchestration.md`, which owns
the cross-agent backlog recovered the same day (rows A1-A16, OC-1..OC-5); this
file does not duplicate those rows. Runtime evidence: `D:\AgentHub\runtime\orchestration\2026-10-26\cline\`
(briefs, manifests, `*.events.jsonl`, reports, `watch.log`).

## Owner direction and policy tension

- 2026-10-26: `registry/fleet-profile.json` -> `dispatchPolicy.cline.enabled = true`
  with an `allowedModels` list. Supersedes the 2026-10-23 20:21 CT direction
  ("only Cursor, Grok and Codex may run agent work") **for Cline only**.
- The 2026-10-15 "one coding host at a time" rule still exists. This batch ran
  three or four Cline processes (remote models only) next to Claude, Codex
  Desktop, OpenCode (OC-3, OC-4), a Devin app and several ACP agent servers
  started by other hosts. Free RAM fell to 0.1 GB at 17:56 CT; the batch watcher
  stopped CL-4 automatically. **Owner decision needed:** whether peer dispatch
  is an accepted exception, and a concurrency cap (recommendation: at most two
  Cline runs while any other host is busy).

## Cost incident (2026-10-26 22:56Z)

An ACP smoke test created a session without selecting a model. Cline's ACP and
new interactive sessions default to `anthropic/claude-sonnet-5.5` on the
usage-billed `cline` provider, so one prompt ("reply ACP-READY") billed
**$0.374193** (149,646 input tokens, session `1793055382350_skMXJ_cli`).
Lessons, now rules:
1. Every ACP, Kanban or TUI session started by an agent must set the provider
   and model explicitly before its first prompt.
2. The account holds usage-billed Cline credit. Any model on provider `cline`
   without the `:free` suffix bills. The owner should check auto-reload at
   `app.cline.bot` (not checked; no CLI surface).
3. A plugin cannot enforce this: the `beforeModel` hook context exposes no
   provider or model (checked 2026-10-26: `snapshot` + `request.{systemPrompt,messages,tools,options{thinking,metadata}}`).
   Enforcement lives in the launcher's allowlist.

## Providers and models (verified 2026-10-26, CLI 3.0.71 / ACP 3.0.74)

| Provider:model | Result | Cost | Use for |
|---|---|---|---|
| `cline-pass:*` | "weekly Clinepass limit reached, resets in 2d 1h" (22:45Z) | subscription | after reset (~2026-10-28 19:45 CT): sustained complex work |
| `openai-compatible:qwen3.8-max` (Alibaba Model Studio) | pong in 6 s, 3k input tokens; CL-1 then failed at 23:07Z after ~400k tokens: "The free quota has been exhausted ... disable 'use free tier only' mode". The endpoint runs on a free-tier quota in free-tier-only mode, so it fails closed instead of billing | free tier (exhausted) | unavailable until the quota resets or the owner changes the plan; do not disable free-tier-only mode without approval |
| `cline:nvidia/nemotron-3-ultra-550b-a55b:free` | small coding task ALL PASS, 46 s, 4 iterations | $0 | tool-heavy work, browser QA, fast routine fixes |
| `cline:poolside/laguna-s-2.1:free` | ALL PASS, 86 s, 7 iterations | $0 | routine implementation, refactors behind tests |
| `cline:cohere/north-mini-code:free` | ALL PASS, 135 s, 7 iterations | $0 | scripting, audits, test generation |
| `cline:thinkingmachines/inkling:free` | 429 daily cap (1,000 req/day shared) | $0 | retry another day |

Notes: every `cline`-provider request carries ~119k input tokens of default
context (vs 3k on openai-compatible). Free models are capped per request, not
per token, so this costs nothing there but makes any paid misroute expensive.
Root cause not established. The free catalogue is
`https://api.cline.bot/api/v1/ai/cline/models` (price 0 and `:free` suffix).

Routing rules: start on a free model; use qwen3.8-max (later ClinePass) for
security/policy-sensitive or multi-file design work; escalate one tier after a
demonstrated failure; review with a different model family than the
implementer; never use a model outside `dispatchPolicy.cline.allowedModels`.

## Permission model

- `--auto-approve true` approves every tool call. `~/.cline/plugins/peer-guard.js`
  (`beforeTool` hook, returns `{skip, reason}`) denies: git push, reset --hard,
  clean -f, branch -D, history rewrites, worktree removal; outward gh actions,
  mutating gh api, gh auth/secret; package publishing; cloud/infra CLIs;
  scheduled tasks, services, Run keys; agent-host administration (`cline auth|schedule|connect|hub|...`);
  environment/credential dumps; disk/power operations; root/home recursive
  deletes; system security settings; reads of `.env`/credential files; writes
  under `D:\Local-AI` (except `cache\temp`).
- It is active only when **both** `AGENTHUB_PEER_GUARD=1` and
  `CLINE_SESSION_BACKEND_MODE=local` are set. Verified live: hub mode, push went
  through to a scratch bare remote; local mode, push blocked and remote empty.
  Interactive TUI/Desktop sessions are unaffected.
- Known gaps: literal-text matching (compound commands can evade it, and a shell
  here-doc that writes a file whose content contains a denied string, such as the
  guard's own test file, is blocked: observed twice in CL-1 run 2; write such files
  with the editor tool); hook
  errors fail open (`hookErrorMode` default `ignore`); not yet AgentHub-owned
  (CL-1 packages it); `Invoke-CodingAgent.ps1`'s Cline contract does not set the
  two variables yet. Until it does, launch Cline only through
  `D:\AgentHub\runtime\orchestration\2026-10-26\cline\Start-ClineTask.ps1`.
- Do not use `cline --worktree`: it creates worktrees under `~/.cline/worktrees`,
  outside the sole approved root `C:\wt`.

## Task registry

| ID | Workstream | Objective | Model | Status | Location | Evidence | Next action |
|---|---|---|---|---|---|---|---|
| CL-1 | D: agent automation | Package the peer guard in coding-agent-dispatch with node tests, audit/apply installer, docs, hash | cline:nemotron-3-ultra:free (run 1 on qwen3.8-max hit its quota) | Integrated: Cline wrote the packaged guard, `Install-ClinePeerGuard.ps1`, 6 node tests and docs; the orchestrator stripped a BOM and recomputed the hash | AgentHub main `cfebd89` | package tests 29/29, dispatcher 97/97, registry 7/7, Validate PASS; deployed with `Install-ClinePeerGuard.ps1 -Apply` (state `repaired`) | none |
| CL-2 | B/C: product QA + browser | Interactive agent-browser QA of the saroshhussain site, fixes with retest | cline:nemotron-3-ultra:free | Integrated and pushed (site deploy triggered). Run 1 was stopped by the loop detector; the final run (179 iterations, $0) found the contact-page heading-order axe violation and added an AlertTitle heading level. The orchestrator made every contact status banner h2 and reverted a hardcoded Windows Chrome path in `playwright.config.ts` and a flipped "Send Message" expectation | saroshhussain main `3505733` | Playwright 343 passed / 57 skipped / 0 failed after rebase onto #29; 9 screenshots in `D:\AgentHub\runtime\orchestration\2026-10-26\cline\CL-2-evidence\`; `CL-2-report.md` | confirm the App Platform deploy |
| CL-3 | A: code health | Characterization tests + refactor of `parseShotList` (CCN 115) | cline:laguna-s-2.1:free, then a Claude implementer | Integrated (tests only). Cline overflowed the 262k context window (about 120k baseline) and left a failing draft; the implementer wrote 42 passing cases and a refactor, but main already had another session's refactor (`c068d11`), so only the tests landed. They pass against that refactor | AgentHub main `e2cbe97` | shot-list + code-stage 53/53, media-studio 419/419, Validate PASS | none |
| CL-4 | D: reliability | Read-only audit of `C:\wt` leftovers for unmerged work | cline:north-mini-code:free, then orchestrator | Done (also reassigned to Devin DV-2 by another session). The Cline run completed but was rejected: it checked the container folders, which are never worktrees. The orchestrator's read-only audit script and report replaced it | `CL-4-report.md`, `CL-4-audit.csv`, `CL-4-work\Audit-WtLeftovers.ps1` | 70 directories: 37 safe, 3 client skipped, 30 review (private-beta WIP, unpushed rexa and documed worktrees) | owner decides on the review list |
| CL-H1 | (recovered) | Cline Desktop repair session in `C:\Repos\natively-cluely-ai-assistant` (outside fleet trees) | — | Failed 2026-10-26 07:25; 18 uncommitted files | that checkout | Cline history `session_1792976520434_tc3m8` | owner: confirm whose repo it is before anyone resumes |

Final outcome (21:20 CT): all four tasks integrated or reported (table above). Root cause of
the evening's memory crashes: a RepoWise post-commit hook (`repowise update`, 23.8 GB) in 25
personal repos, disabled by renaming to `post-commit.disabled-20261026`; client repos untouched.

First-run outcome (18:15 CT): four tasks launched, none completed. Headless resume is
not possible on CLI 3.0.71: `cline --json --id <session>` rejects both a prompt
argument and piped stdin ("JSON output mode requires a prompt argument"), and the
dispatcher's ACP resume runs with auto-approve off (follow-up questions only). An
interrupted tool task restarts fresh. Relaunch serially when other sessions' render
jobs are not holding memory.

## Orchestrator changes (2026-10-26)

- `Invoke-CodingAgent.ps1`: Cline runs get `AGENTHUB_PEER_GUARD=1` and
  `CLINE_SESSION_BACKEND_MODE=local` (also on ACP resume) and `--compaction agentic`;
  `-Model provider:model` for Cline is limited to `dispatchPolicy.cline.allowedModels`.
- `cline/acp-session.mjs` + `acp-dispatch.mjs`: ACP resume requires a provider and model,
  sets both with `session/set_config_option` after `session/load`, and refuses to prompt
  unless the agent confirms them. Reason: Cline reloads a session on its account default,
  `anthropic/claude-sonnet-5.5` (usage-billed), not the session's model (checked with a
  no-prompt load of a free-model session). Live check through the deployed dispatcher:
  reply `resumed-free`, session model `nemotron-3-ultra:free`, total cost $0.
- Tests: `Test-CodingAgentDispatch.ps1` 82/82 (3 new Cline checks), package node tests
  23/23 (2 new ACP refusals), `Test-RegistryHostReferences.ps1` 7/7 (Cline authorized, with
  a guard that only `:free` models may appear on the `cline` provider), `Validate-AgentHub` PASS.
- Deployed as single-file copies to `~/.agents/skills/use-coding-agent/` (backups `*.bak-cline-20261026`).

## Interactive surfaces (verified 2026-10-26)

- TUI: `cline -i -P cline -m nvidia/nemotron-3-ultra-550b-a55b:free --thinking none "<prompt>"` in a
  Terminal-panel tab rendered the Cline Dark theme, status line "Nemotron 3 Ultra (free) ... $0.00",
  Plan/Act toggle, branch and diff summary, auto-approve indicator; the reply `tui-ok` arrived with
  120,869 context tokens at $0.00. A "Get Cline Desktop" promo overlays the first start.
- Desktop (`%LOCALAPPDATA%\Cline\cline-app.exe`): launches signed in; its session list is shared with
  the CLI (headless CLI runs, the TUI run and the CL task runs all appear). The owner was using it live
  during the check, so no prompt was sent from its window. Verified headless instead: Desktop's bundled
  runtime `%LOCALAPPDATA%\Cline\cline-cli.exe` (3.0.74, newer than the npm CLI's 3.0.71) answered
  `desktop-runtime-ok` on `cline:nemotron-3-ultra:free` at $0 with the same `~/.cline` config and lists the
  same plugins (agent-browser, lightweight-chat, peer-guard). `sessions.db` records Desktop runs with
  `source = 'desktop'` (one so far: 2026-10-26 01:02Z, opencode-go/gemini-4-argon, failed, $2.33).
  Prefer this headless check over driving the app's window. Its composer offered Anthropic and OpenAI-compatible
  (Alibaba, exhausted) selections; pick a `:free` model or ClinePass explicitly there too.

## Capability matrix (Cline CLI; evidence from this session unless noted)

| Capability | Cline CLI | Evidence |
|---|---|---|
| Read/edit code, run commands | yes | bench runs: `editor`, `run_commands` tool calls, tests passed |
| Headless/unattended | yes | `--json --auto-approve true -t`; NDJSON `run_result` |
| Resume session | yes | `--id <session>`; ACP `session/load` replayed 2 updates |
| ACP | yes, client verified | live smoke: initialize (protocol 1, loadSession true), session/new, prompt -> `ACP-READY`, session/load |
| MCP | configured, not exercised | 7 remote servers in `cline_mcp_settings.json` (context7, descript, exa, firecrawl, linear, notion, railway), loaded on demand via `lightweight-chat.js` `find_tools` |
| Skills | configured | `~/.cline/skills` -> shared library (111 skills) |
| Plugins | yes | `cline config plugins` lists agent-browser, lightweight-chat, peer-guard; guard hook proven live |
| Interactive browser | in progress (CL-2) | agent-browser plugin + rule `10-browser-windows.md`; result in CL-2 report |
| Subagents | available | `spawn_agent`; subagents get no MCP tools (docs) |
| Agent Teams | yes, verified headless | `/team` prompt on `cline:nemotron-3-ultra:free` with the guard: 2 `teammate_spawned`, 2 `task_start`/`task_end`, 9 `team_mission_log`, 2 `teammate_shutdown` events; completed in 4 lead iterations, $0; teammates wrote `slug.py` and `test_slug.py`, independent rerun ALL PASS. State in `~/.cline/data/db/teams.db`. |
| Kanban | runs; not adopted for execution | Kanban 0.1.70: `node %APPDATA%\npm\node_modules\kanban\dist\cli.js --no-open --host 127.0.0.1 --port 3484 --skip-shutdown-cleanup` served `http://127.0.0.1:3484/agenthub` (HTTP 200, loopback listener only); `kanban task list --project-path <repo>` returned JSON. Blocker: task worktrees go to `~/.cline/worktrees` (`KANBAN_TASK_WORKTREES_HOME_DIR_NAME`), outside the sole approved root `C:\wt`, and default shutdown cleanup deletes task worktrees. Its default Cline model for a card is the workspace default (paid); cards must pass `--cline-provider`/`--cline-model`. Owner decision: allow a `C:\wt`-resolving root for Kanban, or keep it as a viewer only. |
| Scheduling | do not use | `cline schedule` starts the hub and persistent cron: violates the no-scheduled-jobs rule |

OpenCode's equivalent rows are in `opencode-peer-orchestration.md`; other hosts: `registry/fleet-profile.json` -> `hostSurfaces`.

## Appearance

- TUI: `~/.cline/data/settings/global-settings.json` -> `tuiTheme` (env `CLINE_THEME` overrides). Built-in ids only:
  `auto` (default, follows the terminal palette), `dark` (Cline Dark, `#14161b` / `#e8eaed`), `light`, `tokyo-night`,
  `nord`, `one-dark`, `dracula`, `gruvbox-dark`, `catppuccin-mocha`, `solarized-dark`, `solarized-light`. No custom
  theme schema exists. Set to `dark` on 2026-10-26 (closest native match to the AgentHub charcoal palette); backup
  `global-settings.json.bak-theme-20261026`. To use the exact AgentHub palette, set `auto` and give the terminal
  profile that palette.
- Desktop (Tauri, `%LOCALAPPDATA%\Cline\cline-app.exe`): settings live in WebView storage; set appearance in its
  Settings UI. Not changed by agents.

## Runbook

- **Interactive:** `cline` (TUI) or `cline -i`; `/model` to pick provider/model explicitly (never accept the default
  paid model), `/settings`, `/history`, `/compact`. Resume: `cline history` then `cline --id <session>`.
  Desktop: Start menu "Cline". Plan/Act: Tab; auto-approve all: Shift+Tab.
- **Start a guarded task:** write a brief (copy a `CL-*.md`, keep `COMMON.md`), create a worktree with the AgentHub
  helper, then
  `pwsh -NoProfile -File D:\AgentHub\runtime\orchestration\2026-10-26\cline\Start-ClineTask.ps1 -Id CL-n -Brief <brief> -Cwd <worktree> -Provider <p> -Model <m>`.
  It refuses models outside the allowlist, sets both guard variables, writes `CL-n.manifest.json`, runs hidden.
- **Progress:** `pwsh -NoProfile -File D:\AgentHub\runtime\orchestration\2026-10-26\cline\Get-ClineTaskStatus.ps1`
  (state, tool calls, real guard blocks, idle minutes, tokens, cost, commits, dirty files). Idle 10+ minutes = stalled.
- **Take over manually:** stop the dispatched process first (one writer per session), then `cline --id <session>`
  from the same cwd. The session id is the `conv_`/history id in `cline history`.
- **Review and integrate:** read `CL-n-report.md`, diff the branch against its base, rerun the tests yourself.
  Push/PR only with owner approval.
- **No monitoring daemon** by policy. The batch watcher is a bounded foreground loop of the orchestrator session.
- A headless run can leave a `cline.exe --cline-hub-daemon` process; never read run output through a pipe that waits for EOF.
