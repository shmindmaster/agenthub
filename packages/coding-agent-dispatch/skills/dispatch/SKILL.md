---
name: dispatch
description: Runs a task on another coding-agent host and returns its output. Use when asked to delegate, hand off or run work on another agent, or to list callable hosts.
metadata:
  version: "0.13.0"
---

# Dispatch to another coding agent

`Invoke-CodingAgent.ps1` (in this skill directory) is the only place that knows each host's verified command. Run it; do not build a host CLI line by hand, launch a GUI, or use a subagent that imitates another product.

## Locate the dispatcher

Set `$dispatcher` to the absolute path of `Invoke-CodingAgent.ps1` beside this
`SKILL.md`, using the skill location supplied by the host. Plugin caches and
host-specific skill links have different paths; do not assume a shared install.
The shared `%USERPROFILE%/.agents/skills` library is intentionally empty under
the plugin-only fleet policy.

If the host does not supply a skill location, an explicitly configured
`AGENTHUB_ROOT` may identify the checkout:

```powershell
$dispatcher = Join-Path $env:AGENTHUB_ROOT 'packages/coding-agent-dispatch/skills/dispatch/Invoke-CodingAgent.ps1'
```

Confirm that the file exists. If neither source identifies it, stop and report
the missing installation; do not search credentials or guess a cache version.

## Steps

Heavy work (test suites, builds, renders) does not run on this PC and is not
dispatched to a remote operator droplet. Run it on Daytona:
`node <AgentHub>/scripts/daytona-run.mjs --owner <project> -- <command>`.
Dispatch only chooses which coding agent does the task.

Plan routes (Qwen, Z.ai, MiMo) for opencode, kilo, cline and factory are in
`references/hosts.md` -> Plan routes. On Windows, keep Claude and Codex on
their native accounts by default. Use `-Auth` to show sign-in commands, and add
`-HostId` to narrow the output.

1. List callable hosts. Take "callable" from this output, not memory.

   ```powershell
   pwsh -NoProfile -File $dispatcher -List
   ```

   Rows are `id`, `callable|routed|refused`, reason. A refused row stays refused: report it and stop.
   Callable means the registry, autonomy profile and executable checks pass;
   it is not a live authentication, quota, MCP-health or ACP-protocol check.

2. Write the task to a UTF-8 file and run one host, with `-Cwd` set to the task repository.

   ```powershell
   pwsh -NoProfile -File $dispatcher -HostId <id> -PromptFile <absolute-task-file> -Cwd C:\Repos\example
   ```

   Put temporary task files under `%LOCALAPPDATA%/AgentHub/tmp`, not in the
   repository. Use `-Prompt` only for a short single line with no quotes. Pass
   `-TimeoutSec 7200` for program-scale work. `-ShowCommand` prints the command
   without starting anything. It does not prove that a host will execute it.

   `-Model <id>` picks the model for codex, grok, opencode, cline,
   factory, devin, kilo, mimo-code and qwen. Any model the host can reach is
   accepted: `allowedModels` in `dispatchPolicy` records the smoke-verified
   models and does not limit the choice. An unlisted model adds one stderr
   note and runs. Only a malformed id is refused, plus the two
   subscription-only rules in `references/hosts.md` (no `opencode/` Zen
   wallet, MiMo on the Token Plan only).

   Subscription plan routes (smoke-verified 2026-11-14) for opencode, kilo and
   factory: Qwen Token Plan, Z.ai GLM Coding Plan and MiMo Token Plan. Exact
   ids are in `references/hosts.md` -> Plan routes.
   For Z.ai Coding Plan, use `-HostId opencode -Model zai-coding-plan/glm-5.4`.
   See the host reference for the Windows tool limits.

   On Windows, `-HostId zcode` uses the bundled CLI and the existing standalone
   ZCode provider profile. For native headless Browser Use, run
   `zcode/Install-ZCodeBrowserRuntime.ps1` beside this skill once, then add
   `-ZCodeBrowser`. It opens a fresh headless Edge profile.

   `-Role <role>` picks an OpenCode agent or a Factory custom droid: `peer` (default), `engineer`,
   `reviewer` or `tester` (OpenCode also takes `researcher`). Factory maps `engineer`,
   `reviewer` and `tester` to native droids (`dispatchPolicy.factory.roles`,
   deployed from `packages/coding-agent-dispatch/factory/droids` with
   `Install-FactoryDroids.ps1`); every other host refuses a role other than
   `peer`.

   `-ReadOnly` runs the task in a read-only mode the host itself enforces.
   It works on claude, codex, factory and qwen; every other host refuses it
   with exit 3 and never falls back to a writable run. Use it for reviews and
   audits, and never rely on prompt wording to keep a run read-only.
   `-List -ReadOnly` prints the hosts that support it. Details are in
   `references/hosts.md`.

3. Return the child's output and exit code. Do not restate its flags.
   Remove only task files and scratch created for this dispatch after reading
   the result. Preserve the caller's files and any evidence needed for a failure.

Exit codes: 0 child succeeded; 2 launch failure; 3 refusal (policy, autonomy, input, or missing executable); 4 timeout (process tree killed); other child codes pass through, and native 2-4 map to 1. Logs: `%LOCALAPPDATA%/AgentHub/runtime/coding-agent-dispatch/*.out|.err`.

## Rules

- Concurrent hosts require separate claims and non-overlapping write scopes.
  Before starting another host, check free RAM; below 4 GiB, finish or pause work
  first. Shared history never authorizes overlapping edits.
- Assigning backlog work to the fleet (owner direction, 2026-11-10): spread it
  over hosts instead of loading one. Default to two sessions per host that has
  allowance and RAM for them (for example two Grok, two OpenCode, two
  Antigravity CLI), fewer when free RAM is under 4 GiB or a plan is near its
  limit. Give each session a batch of several related backlog items of real
  size, not one small item. Batches never share files: split by repository or
  by area inside one, and give each session its own worktree under
  `C:\wt\<repo>\<task>`. Claim every item in Linear (`agent:<host>`, In
  Progress) before launch. The session that wrote a change never gives its
  final review; a different host reviews it.
- Every brief ends with the pull-request rule: open as draft, mark it ready for
  review (`gh pr ready`) when the work and tests are done, because that starts
  the Sentry Seer review and a draft is never reviewed, then fix or answer
  every finding before reporting done.
- Every child runs windowless and never takes focus. Never open the Cursor IDE, Antigravity, OpenCode Desktop, Warp, VS Code or any GUI to get around a refusal.
- Never run a paid probe or smoke to test availability. Readiness comes from `-List`, the account's included allowance, and `registry/fleet-profile.json` (`dispatchPolicy`, `hostSettings`), which can disable any host with a reason. Help output proves a command contract, not authentication or allowance.
- Never log in, change credentials, or accept a paid fallback automatically. If an auth check fails, keep the host disabled and ask the owner to log in from their own terminal.
- Account-authenticated children have their host-specific provider-key overrides
  stripped. A separately authorized plan credential is not an account login or
  permission to use another paid provider. Never print credential values.
- Qwen's route carries the MiMo Token Plan in the child environment only:
  `MIMO_API_KEY` and `MIMO_BASE_URL` become `OPENAI_API_KEY`, `OPENAI_BASE_URL`
  and `OPENAI_MODEL`, both `MIMO_*` variables must be present and plan-shaped,
  and the other providers' keys are scrubbed first. `-ShowCommand` prints the
  variable names, never values. The stored `~/.qwen` configuration is not read
  or written.
- A local headless command does not authorize cloud execution. `jules`, `cursor-cloud` and `copilot-agent` are refused. `devin-cloud` is the one cloud route (owner direction 2026-11-19): it creates a Devin Cloud session through `Invoke-DevinCloud.ps1` only while `dispatchPolicy.devin-cloud` is enabled with its `cloudBudgetAuthorization`, at `max_acu_limit` 10 unless the task passes `-MaxAcu`, with at most 3 concurrent agenthub sessions. Its key comes from `op read` through the 1Password service account; never set or persist a Devin key variable. These caps bind only the adapter: the Devin MCP lane is uncapped by AgentHub, so pass `max_acu_limit` 10 there by convention. Lanes, waiting and the Devin MCP headers helper: `references/hosts.md` (Devin).
- A dispatch does not authorize client access, external messages or deployment.
- An ACP command listed in help proves only an entry point. Record protocol
  initialization, session operations and authenticated inference separately.

## Recovery

If installation, policy, authentication or allowance prevents a run, report the
blocking gate and keep the host refused. Do not retry through another identity,
provider, GUI, cloud mode or permission bypass. On timeout, return exit 4 and
the available output; the runner stops its owned process tree. Never kill an
unrelated host or service to recover.

## Host details

Read `references/hosts.md` when choosing a model, a Factory or OpenCode role or a read-only run, dispatching to Cline, OpenCode, Factory, Devin, Warp or Copilot, resuming a Cline session, or auditing a host plugin (`Install-*.ps1`).
