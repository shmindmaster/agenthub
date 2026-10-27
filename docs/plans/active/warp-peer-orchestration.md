# Warp peer orchestration

## Owner direction

2026-10-26: enable Warp dispatch local-only (no cloud), run one smoke test on an
economical model, and start Warp tasks only once machine load drops. Theme and
statusline work are deferred. Cloud runs (`run-cloud`), cloud environments,
schedules, handoff and Warp Factories stay prohibited (`dispatchPolicy.warp.scope`).

## Verified state (2026-10-26)

| Item | State | Evidence |
|---|---|---|
| Install | Warp v0.2026.10.14.08.27.stable_03; `oz.cmd` = `WARP_CLI_MODE=1 warp.exe`. Warp Agent CLI v0.2026.10.21.08.25.stable_02 installed at `%LOCALAPPDATA%\Warp\bin\warp.cmd`, first on the user PATH | `oz --version` |
| Auth | Account login works with `WARP_API_KEY` removed | `oz whoami` |
| Models | 130 listed; every Warp-hosted model spends Warp credits | `oz model list`; docs.warp.dev/agents/cli/models-and-usage |
| Smoke | `agent run --model glm-5.3-flash-fireworks --no-snapshot` exit 0, 30 s, `READY` | run `01a17a80-1423-7e43-bb96-7aafdd060bc1` |
| Prior Warp work | 7 cloud runs, Feb–Mar 2026, all terminal; no schedules | `oz run list --output-format json` |
| Guard | Child env blocks `git push` (push URL rewrite) and `gh` (empty config dir); local destructive commands are not guarded | `dispatchPolicy.warp.guard` |
| MCP | `file_based_mcp_enabled = false`; per-run `--mcp <path>` is the documented route; not exercised | W-1 |
| Browser | Computer Use is cloud-sandbox only; local Warp has no native browser | `hostSurfaces` warp-local |
| Cost visibility | No usage command in `oz`; `/usage` and the `credit_usage` statusline item are in the interactive Agent CLI | CLI start screen |

## Start gate

Start Warp tasks only when all of these hold: CPU < 50 %, memory < 70 %, no
media-studio builds running, and no other dispatched coding run active in the
target repository. Every task must finish before the 01:00–07:00 update window.
Run one or two Warp tasks at a time, not four at once.

## Task registry

| ID | Workstream | Objective | Model | Status | Worktree | Acceptance |
|---|---|---|---|---|---|---|
| W-1 | D: agent automation | Pass AgentHub MCP config to Warp runs via `--mcp`, add dispatcher tests | glm-5.3-fireworks | Integrated (e6f1094, 89/89 dispatch tests); live tool call not yet exercised | `C:\wt\agenthub\warp-mcp` (from `worktree-warp-peer`) | dispatch tests pass; one run's ndjson shows the tool call |
| W-2 | A: code health | Characterization tests, then decompose `parseToml` (`src/doctor/parsers.js`, CCN 92) with no behaviour change | glm-5.3-fireworks | Integrated (ca82ec5; 22 tests added, 58 pass / 0 fail) | `C:\wt\agenthub\warp-parse-toml` | `node --test test/doctor` passes before and after; CCN lower |
| W-3 | A: code health | Split `qaStage` (`packages/media-studio/kit/marketing/lib/stages/qa.mjs`, CCN 42) into helpers behind existing tests | glm-5.3-flash-fireworks | Superseded: reassigned to Devin DV-1 on 2026-10-26 (never started here) | `C:\wt\agenthub\devin-qa-stage` | `npm test -- packages/media-studio/tests/review-hardening.test.mjs` passes |

Not taken (already owned): `validateCampaign`, `lintSpec` (Factory F-1),
`parseShotList` (F-1, Cline CL-3), `repowise_bridge.py` (F-2), `buildRatioPlan`
(`compose.mjs` was changed today).

## Runbook

```powershell
pwsh -NoProfile -File packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1 `
  -HostId warp -Cwd C:\wt\agenthub\<task> -PromptFile <brief.md> -Model glm-5.3-fireworks -TimeoutSec 3600
```

The run's stdout is ndjson; `run_started.run_id` and `conversation_started.conversation_id`
go in the registry row. Each run is visible at `https://oz.warp.dev/runs/<run_id>`
and can be continued interactively in Warp Desktop. Rollback: set
`dispatchPolicy.warp.enabled` to false; restore Warp settings from
`%LOCALAPPDATA%\warp\Warp\config\settings.toml.bak-agenthub-peer-20261026`.
