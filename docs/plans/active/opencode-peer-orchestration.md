# OpenCode peer orchestration

Started 2026-10-26 by the Claude orchestrator session, on the owner's request to
make OpenCode a first-class execution peer and delegate substantial work to it.
This file is the durable task registry, routing policy and runbook. It
survives any single session. Runtime evidence lives under
`%LOCALAPPDATA%\AgentHub\runtime\orchestration\2026-10-26\` (junction to
`D:\AgentHub\runtime\...`): task briefs, reports and dispatch logs.

Sibling registry: Cline peer work (CL-1..CL-4) is tracked by a separate
orchestrator session in `docs/plans/active/cline-peer-orchestration.md`.

## Owner direction and policy tension

- 2026-10-26: OpenCode re-enabled in `registry/fleet-profile.json` ->
  `dispatchPolicy.opencode`. This supersedes the 2026-10-23 20:21 CT direction
  ("only Cursor, Grok and Codex may run agent work") **for OpenCode only**.
- The 2026-10-15 "one coding host at a time" rule still exists in the global
  policy. This batch ran five OpenCode sessions on one shared OpenCode service
  (remote models only, no local model or GPU work) while Codex Desktop and
  Claude were also running. Free memory stayed at 8 GB or more. The owner
  should confirm whether peer dispatch is an accepted exception to that rule.

## Lifecycle

`Discovered -> Prioritized -> Assigned -> Running -> Review -> Verified -> Integrated -> Done`,
plus `Blocked` and `Failed`. "Done" in a report is not a rung. Integration
states use the global ladder: merged to dev, in main, deployed,
production-verified.

## Task registry

Recovered 2026-10-26 from dispatch logs, `C:\wt`, branches, plans, open PRs
and agent session stores (personal `shmindmaster` tree only; client trees were
not inspected).

| ID | Objective | Original agent | Current owner | Status | Location | Model | Evidence | Next action |
|---|---|---|---|---|---|---|---|---|
| A1 | lawli AGENTS.md split | Claude (dispatch 245e1bf3) | — | Done (in main) | lawli#231 | — | merged 10/26 | none |
| A2 | documed AGENTS.md split | Claude (dispatch 029b518f) | owner | Review | `C:\wt\documed\agents-split-20261026`, `16043f6`, local only | — | no remote branch | owner decides (documed frozen) |
| A4 | Azure Container Apps cloud render | not recorded | OpenCode OC-4 (review) | Review | agenthub#81 | — | CI 9/9 green, no review | see OC-4 |
| A5 | duplicate-hero rubric fix | not recorded | owner | Review (draft PR) | agenthub#83 | — | CI green | owner review |
| A6 | heatlot SH-3483 review fixes | not recorded | owner | Review | heatlot#46 | — | CI 5/5 green | owner review |
| A7 | 30 synthetic rules-eval cases | not recorded | OpenCode OC-2 | Running | subops `chore/synthetic-rules-eval-cases`, local only | glm-5.3-flash | `20c634e3` | see OC-2 |
| A8 | private-beta gate | not recorded | unassigned | Stalled | subops `wip/private-beta-20261026` (local), coledger `wip/private-beta` | — | WIP snapshots | scope with owner |
| A9 | retrieval OSS resource contract | not recorded | OpenCode OC-1 | Running | local-ai-platform `fix/retrieval-oss-resource-contract` (13 commits, 41 files) | deepseek-v4-pro | no PR; overlaps merged #41 | see OC-1 |
| A9b | scheduler / lock / hidden-descendant fixes | not recorded | unassigned | Stalled | local-ai-platform `wip/*-20261026` (3 branches) | — | pushed, no PR | reconcile after OC-1 |
| A10 | rexa vlc-v2 review fix | not recorded | unassigned | Stalled | rexa `fix/vlc-v2-review-fixes-20261026` | — | pushed, 1 file, no PR | owner (rexa mobile-deferred) |
| A11 | Sienna narration + API-key + resume validation | not recorded | owner | Stalled | agenthub local `main` has unpushed `9417f2f`; `wip/agenthub-claude-apikey`, `wip/resume-validation`, `wip/cloud-render` | — | not on origin/main | owner: push or branch |
| A12 | fleet repo-standard migration (milestone 4) | DeepSeek workers planned | OpenCode OC-3 | Running | `docs/plans/active/fleet-repo-standardization.md` | minimax-m3 | 1 of 16 done | see OC-3 |
| A13 | Rexa EAS recreate | — | owner | Blocked | mobile-scope-guard milestone 6 | — | deferred by owner | — |
| A14 | Slack milestones 2-5, content-controls live gates | — | owner | Blocked | plans | — | Slack app/OAuth grant and budget needed | owner |
| A15 | recuts-lane voice re-gate | Cursor | Cursor | Stalled | FLEET-BOARD incident | — | open since 10/25 08:45 | Cursor lane |
| A16 | RESUME8 host probes | Cline, OpenCode | — | Done | dispatch logs 10/24 | glm-5.3-flash | `*_OK` markers | none |

Unrecoverable: no prompt files are kept by the dispatcher, so original task
text for runs before 2026-10-26 is inferred from output only.

### OpenCode assignments (this batch)

Briefs: `D:\AgentHub\runtime\orchestration\2026-10-26\OC-*.md`; shared rules in `COMMON.md`.
Every run: dispatcher `-HostId opencode`, agent `peer`, shared service, `-TimeoutSec 5400` (OC-5: 900).

| ID | Objective | Model | Session | Worktree / cwd | Acceptance |
|---|---|---|---|---|---|
| OC-1 | Classify the 13 retrieval-branch commits against main, review the remainder (incl. scheduled-task mechanisms), run tests | deepseek-v4-pro | `ses_e85a2f8baffed51jtQcGsv1OYO` (continued once via `opencode run --session`) | `C:\wt\local-ai-platform\opencode-retrieval-review` (`opencode/retrieval-reconcile-20261026`) | every commit classified with evidence; tests run; report |
| OC-2 | Validate the 30 synthetic eval cases against rule logic; run harness | glm-5.3-flash | `ses_e85a2ef83ffeloYOTc56dGDQJA` | `C:\wt\subops\synthetic-data` | all cases verified; harness passes; report |
| OC-3 | Advance repo-standard migration by one repo in a `C:\wt` worktree | minimax-m3 | `ses_e85a2e6a4ffeOZgUZbFpvmZ3Ua` | agenthub (read-only) + new worktree | checker passes for the target; committed locally |
| OC-4 | Independent high-risk review of agenthub#81 | gemini-4-argon | `ses_e85a2dd25ffeiFp5WIKfbUbzrr` | `C:\wt\agenthub\pr81` (read-only) | verdict; file:line findings; local tests run |
| OC-5 | Browser workflow smoke via `agent-browser` | qwen3.8-flash | `ses_e85a2d646ffeMxjFfda8VsbZRO` | `...\2026-10-26\oc5` | 3+ screenshots; per-step pass/fail |

Results are recorded in the section "Batch results" below.

### Factory Droid assignments (this batch)

Added 2026-10-26 by a second Claude orchestrator session, on the owner's request to make Factory Droid a first-class peer with 3–4 substantial tasks. Factory runs on the account login (team tier). Nothing in this batch touches the OpenCode rows above. The batch uses `droid exec` directly, not the dispatcher, because `dispatchPolicy.factory.enabled` is still `false` (owner direction 2026-10-23). F-4 builds the governed dispatcher path; the owner decides whether to enable it.

Factory runtime files live in `D:\AgentHub\runtime\orchestration\2026-10-26\factory\`:
- briefs `F-*.md` and shared rules `COMMON.md`
- `runtime-settings.json`: 9 `permissionRules` blocks, verified with `droid rules check`. They block git push, `git -C`, reset --hard, clean/stash, branch delete, gh writes, publish, cloud CLIs and scheduled tasks.
- event logs `F-*.jsonl` (stream-json)
- reports `F-*-report.md`

Prior Factory work, recovered from `~/.factory/sessions`:
- "Program D on Factory" (2026-10-21/22): sessions `f166e805` (agenthub) and `a3dfe483` (local-ai-platform). PRs #58 and #35 are merged. The last state was a bounded wait, with "Deployment and Film 18 gates have not run". Marked **Stalled/Superseded**: Factory was disabled on 10-23, and the remaining items are deployment and media gates the owner must schedule.
- H100 custom-model probes (2026-10-25): synthetic, **Done**.

| ID | Objective | Mode | Model(s) | Session | Worktree / branch | Acceptance |
|---|---|---|---|---|---|---|
| F-1 | Characterization tests, then decompose `validateCampaign` (CCN 208), `parseShotList` (115) and `lintSpec` (102) with no behaviour change | Mission (`--mission --auto high` + rules) | orch gpt-6-luna/high, worker gpt-6-luna/high, validator gemini-3.8-flash/high | `d565d8c7-054b-4f7d-9715-92d98b7c651b` | `C:\wt\agenthub\factory-complexity-mission` (`worktree-factory-complexity-mission`) | media-studio tests green; messages byte-identical; only allowed files |
| F-2 | Mine bug classes in `repowise_bridge.py` (health 2.47), fix remaining defects test-first, simplify | exec `--auto medium` | gemini-3.8-flash/high | `b71bd10b-018f-4fb6-ab37-e51684fe4daa` | `C:\wt\agenthub\factory-repowise-bridge` | unit and integration tests; failing-first test per fix |
| F-3 | saroshhussain e2e baseline, triage, fixes (no copy changes), case-study regressions, browser smoke screenshots | exec `--auto medium` | gpt-6-luna/high | `6d4698c7-b05a-41c7-b4b9-c9a709713ece` | `C:\wt\saroshhussain\factory-e2e-case-studies` | classified results; screenshots in `F-3-artifacts` |
| F-4 | Governed Factory dispatcher path: allowlisted `-Model`, `--auto medium`, `-o json`, `--settings` rules; `enabled` stays false | exec `--auto medium` | glm-5.3-flash/high | `0959239d-0d37-427a-926f-aa2d4278480e` | `C:\wt\agenthub\factory-dispatch-adapter` | `Test-CodingAgentDispatch.ps1` and `Validate-AgentHub.ps1` pass; no live dispatch |

Factory credit probe (one-line prompt, ~14–17k tokens of system context) on 2026-10-26:

| Model | Credits |
|---|---|
| gpt-6-luna | 651 |
| glm-5.3-flash | 827 |
| gemini-3.8-flash | 4,382 |
| gpt-6-sol | 14,089 |

Credits ≈ tokens × the documented multiplier. `droid exec` has no spend or turn flag, so each run is bounded by `timeout` (F-1: 7200 s; the others: 5400 s) and by the low-multiplier model choice. Escalate one tier only after a demonstrated failure.

## Model routing and cost policy

Verified 2026-10-26 by a one-word prompt per model through the configured Go
endpoint (`providers.opencode.baseURL = https://opencode.ai/inference/go/v1`):

| Tier | Models that route | Use for |
|---|---|---|
| Routine (cheapest) | glm-5.3-flash, qwen3.8-flash, deepseek-v4.1-flash | validation, test generation, summaries, browser smoke, progress reconciliation |
| Value implementation | minimax-m3, glm-5.3, kimi-k2.7-code | sustained feature work, mechanical migrations |
| Hard reasoning | deepseek-v4-pro | branch archaeology, complex debugging |
| Premium / independent review | gemini-4-argon | high-risk reviews from a different model family than the implementer |

Not routable today:
- `*-free`, big-pickle: "Model is unavailable" on Go; "Free usage limit reached" on Zen.
- claude-sonnet-5-5, gpt-6.1-sol: "Model is unavailable" on Go.

Prices in the Console table are USD per 1M tokens (input / output / cached
read / cached write). The service's `session.list` reports a per-session
`cost` in USD.

Rules:
1. Start with the cheapest tier likely to succeed. Escalate one tier after a
   demonstrated failure: wrong result on review, two unproductive loops, or a
   timeout with no artifact. Record the escalation in the registry.
2. A review never uses the implementer's model.
3. `dispatchPolicy.opencode.allowedModels` is the hard allowlist. The
   dispatcher refuses any other `-Model`. Add a model only after a probe.
4. Extra-usage credit is $0 and auto-reload is not enabled, so a run cannot
   bill beyond the Go allowance. Do not enable either without owner approval.

## Permission model

- Global `opencode.json` -> `policies` (deny, every agent, cannot be loosened):
  - git: force push, `reset --hard`, `clean`, `branch -D`, `filter-branch`, ref deletion.
  - deletion and disks: recursive root/drive deletes, disk formatting.
  - persistence: scheduled-task, service and Run-key creation.
  - cloud: deletes.
  - credentials: `opencode auth export`, `gh auth token`.
- `agents.build.permissions` (interactive): built-in allow-all plus `ask` for
  `git push`, `gh pr create/merge/close`, `gh release create`, `npm publish`,
  `railway up`, `az`, `doctl`.
- `~/.config/opencode/agents/peer.md` (dispatch): allow-all local dev,
  but denies:
  - reads of `.env` and auth files;
  - edits under `D:/Local-AI`;
  - `question`;
  - `git push`, `gh pr|issue|release|api|repo`, `npm publish`;
  - cloud CLIs and `opencode auth`.

  It is needed because `run --auto` approves every `ask`.
- Live check (session `ses_e85a3a803ffenddgN4INwuG37e`): edit, add and commit
  were allowed. `git push` was denied by the agent and `git reset --hard` was
  blocked by policy. The bare remote stayed empty.
- Known gap: shell patterns match literal command text. A compound or
  reordered command can evade a pattern, so the briefs repeat the rules.
- Known gap: the policies and the `peer` agent live in user config, not yet in
  an AgentHub package. `Sync-AgentHub` round-trips `opencode.json` and only
  merges `mcp`, so they survive syncs. Moving them under registry ownership is
  a follow-up.

## ACP

`opencode acp` (protocol 1) passed a live client check on 2026-10-26:
initialize, `session/new`, `session/set_config_option model`, a real prompt
(`ACP-READY`, `end_turn`) and `session/load` replaying 12 updates. Client:
`scratchpad\acp\acp-smoke.mjs`. ACP starts a private server, so its sessions
are separate from the shared service. Use ACP for an ACP-capable client
(Zed); use the dispatcher plus the shared service for orchestrator handoff.
ACP is not a general agent-to-agent bus.

## Runbook

- **See progress (read-only):**
  `pwsh -NoProfile -File D:\AgentHub\runtime\orchestration\Get-OpenCodeTaskStatus.ps1`
  (add `-Match '.'` for every session). Idle for more than 10 min with no new
  tokens means stalled.
- **Work alongside in the TUI or Desktop:** the shared service
  (`opencode service status`, `http://127.0.0.1:28894`) holds every
  dispatched session.
  - Open the task's directory with `opencode`, then `/sessions` (or `Ctrl+X`
    `L`), and pick the `OC-*` title.
  - To continue one by ID: `opencode run --session <id> "<message>"` or
    `opencode mini --session <id>`.
  - Desktop shows the same sessions per project.
  - Stop the dispatched writer before typing into its session, so there is
    one writer per session.
- **Assign a new task:** write a brief (copy an `OC-*.md`, include
  `COMMON.md`), create a worktree with the AgentHub helper, then run
  `pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\use-coding-agent\Invoke-CodingAgent.ps1" -HostId opencode -PromptFile <brief> -Cwd <worktree> -Model <allowed> -Title "OC-n ..." -TimeoutSec 5400`.
  Add a registry row.
- **Change the default or allowed models:** probe first
  (`opencode run --model opencode/<id> "Reply READY"`), then edit
  `dispatchPolicy.opencode`, then run `scripts/Validate-AgentHub.ps1`.
- **Recover a failed run:** the dispatcher `.out` log (written at exit) has
  every JSON event, including `sessionID`. Resume with
  `opencode run --session <id> --agent peer --auto "continue; ..."` from the
  same cwd, or re-dispatch with a narrower brief.
- **Review and integrate:** read `OC-n-report.md`, then diff the worktree
  branch against its base and run the repo's tests yourself. Push or open a PR
  only with owner approval, since the `peer` agent cannot.
- **No monitoring daemon** is installed, by policy (no scheduled jobs).
  Progress checks are manual or orchestrator-driven.

## Batch results

Each finished task was checked by the orchestrator against source evidence,
not only against the OpenCode report.

| ID | Agent status | Orchestrator verification | Cost (USD, service) | Lifecycle | Next action |
|---|---|---|---|---|---|
| OC-1 | done (rev. 2) | Rev. 1 classified against a stale local `main`. The orchestrator fetched GitHub `main` over HTTPS (`c84c8e1`, PR #41 merged 2026-10-26T21:07Z) and continued the same session. Rev. 2: all 13 commits are on `main`, so the branch has zero remainder. Orchestrator `git grep` confirmed the scheduled-task code on `origin/main`. | 1.32 | Verified | Drop branch `fix/retrieval-oss-resource-contract` and its review worktree. Owner decides the policy fix below. |
| OC-2 | done | Orchestrator re-ran `pnpm eval:rules --cases eval/rules/cases/synthetic` on node 24.20.0: 30 cases, precision/recall 100%, exit 0, tree clean. | 0.07 | Verified | Owner approval to push `chore/synthetic-rules-eval-cases` and open a PR (the branch is still local only). |
| OC-3 | done | Fleet before: 19 repos, 607 checks, 55 failures. Target: `tgiagency`, chosen because its 2 `broken-link` failures were the smallest set fixable by a tracked change; the 1-failure repos fail on gitignored machine state. Commit `fee8a00` on `chore/repo-standard-20261026` in `C:\wt\tgiagency\repo-standard-20261026` (2 lines, 2 files). Orchestrator check: `Check-RepoStandard -Repo tgiagency` on main shows exactly those 2 broken links, and `git grep` finds 0 of them in the worktree. The checker audits roster paths only, so the "after" pass is evidenced by grep, not by a checker run. | 0.25+ | Verified | Owner approval to push and open a PR; then milestone-4 count becomes 2 of 16. |
| OC-4 | done: **request-changes** | Confirmed F-01 (`validate-sync.mjs:271` omits `allowAsrAnchored`; `validate-word-sync.mjs:28-29` passes it), F-02 (`picture-gates.mjs:119` `clockAccepted` ignores `report.ok`), Gemini key in the query string (`cloud-ai.mjs:134`), and `Promise.all` chunk fan-out (`cloud-render.mjs:372`). **Rejected:** F-03's claim that `claude-opus-5-5` is an invalid model id. It is current, and the reviewer model's knowledge was stale. F-03's paid-spillover concern stands. Worktree stayed clean. | 0.70 | Review | Owner or implementer fixes F-01, F-02, F-04 and the spillover part of F-03 before merging #81. |
| OC-5 | done: all 5 steps pass | Screenshots 01-04 exist; orchestrator viewed `03-acp.png` (ACP page reached via site search). No console errors, no 4xx/5xx, no overflow at 375 px. | 0.06 | Verified | none |

### Policy finding raised by OC-1 (owner decision)

`shmindmaster/local-ai-platform` `main` (`c84c8e1`, PR #41) contains:
- `remote/kb-server/client/Register-KbRepoPush.ps1:31,35`: a daily `KbServer-RepoPush` task;
- `remote/kb-server/client/Install-KbTunnel.ps1:29-35`: an at-logon `KbServer-Tunnel` task with `RestartCount 999`;
- `remote/kb-server/systemd/kb-repo-sync.timer:6`: `OnUnitActiveSec=5min`, plus `Restart=always` units.

These conflict with the global no-scheduled-jobs rule. As of 2026-10-26 no
`KbServer-*` task is registered on SH-DESKTOP (all tasks visible to the user
were enumerated). The replacement OC-1 proposed is a capability-invoked
tunnel start from `query.ps1 -Remote` and a manual repo-ref push.
