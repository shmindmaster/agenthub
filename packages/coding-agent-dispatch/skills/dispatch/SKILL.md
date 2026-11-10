---
name: dispatch
description: Runs a task on another coding-agent host and returns its output. Use when asked to delegate, hand off or run work on another agent, or to list callable hosts. The enabled hosts are set by dispatchPolicy in fleet-profile.json; never assume Codex or Claude.
metadata:
  version: "0.4.3"
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

3. Return the child's output and exit code. Do not restate its flags.
   Remove only task files and scratch created for this dispatch after reading
   the result. Preserve the caller's files and any evidence needed for a failure.

Exit codes: 0 child succeeded; 2 launch failure; 3 refusal (policy, autonomy, input, or missing executable); 4 timeout (process tree killed); other child codes pass through, and native 2-4 map to 1. Logs: `%LOCALAPPDATA%/AgentHub/runtime/coding-agent-dispatch/*.out|.err`.

## Rules

- Concurrent hosts require separate claims and non-overlapping write scopes.
  Before starting another host, check free RAM; below 4 GiB, finish or pause work
  first. Shared history never authorizes overlapping edits.
- Every child runs windowless and never takes focus. Never open the Cursor IDE, Antigravity, OpenCode Desktop, Warp, VS Code or any GUI to get around a refusal.
- Never run a paid probe or smoke to test availability. Readiness comes from `-List`, the account's included allowance, and `registry/fleet-profile.json` (`dispatchPolicy`, `hostSettings`), which can disable any host with a reason. Help output proves a command contract, not authentication or allowance.
- Never log in, change credentials, or accept a paid fallback automatically. If an auth check fails, keep the host disabled and ask the owner to log in from their own terminal.
- Account-authenticated children have their host-specific provider-key overrides
  stripped. A separately authorized plan credential is not an account login or
  permission to use another paid provider. Never print credential values.
- A local headless command does not authorize cloud execution. `devin-cloud`, `jules`, `cursor-cloud` and `copilot-agent` are refused.
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

Read `references/hosts.md` when dispatching to Cline, OpenCode, Factory, Devin, Warp or Copilot, resuming a Cline session, or auditing a host plugin (`Install-*.ps1`).
