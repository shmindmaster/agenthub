---
name: use-coding-agent
description: Use when a coding agent should run a task on another coding-agent host. Claude and Codex are the primary orchestrators and can call any host this dispatcher lists as callable.
metadata:
  version: "0.2.0"
---

# Use a coding agent from another coding agent

Claude and Codex are the primary orchestrators. Any host that loaded this
skill can call the same dispatcher. The script is the only place that knows
the verified command for each host. Do not invent a flag, a subagent that
pretends to be another product, or a GUI launch.

The script is `Invoke-CodingAgent.ps1` in this skill directory. After
deployment that is:

`%USERPROFILE%\.agents\skills\use-coding-agent\Invoke-CodingAgent.ps1`

Claude reads the same files through the `~/.claude/skills` junction.

## 1. See who can be called

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\use-coding-agent\Invoke-CodingAgent.ps1" -List
```

A row is `id`, `callable|routed|refused`, and a short reason. `cursor` has a
configured alias to `cursor-agent`, currently refused by its interactive
autonomy profile; `windsurf` routes to the local `devin` CLI.
Aliases enforce their own policy and the target's policy and autonomy profile.
Refused rows stay refused. Help verification establishes a command contract;
authentication, allowance and smoke evidence establish readiness separately.

The 0.2.0 contracts cover Claude, Codex, Cursor Agent, Qwen Code, Gemini,
Grok, OpenCode, Antigravity CLI, Factory Droid, Cline, Copilot, Amp, Devin,
Qoder and local Warp/Oz. `registry/fleet-profile.json` -> `dispatchPolicy`
can disable each contract with a reason and owner action. The current verified
free routes are Devin (`swe-2-medium`), also used by the Windsurf alias,
and OpenCode (`opencode/big-pickle`).

Owner gates recorded in this repair:

| Host | Required step before enabling |
| --- | --- |
| Cursor Agent | Owner runs `agent login` in their own terminal, then one authorized smoke. Use `cursor-agent` directly; the Cursor IDE alias also requires an approved unattended autonomy profile. |
| Factory | Owner opens `droid` and runs `/login`, then one authorized smoke. |
| Hermes | Restore the missing executable through official installation/setup; verify help and smoke. |
| Qoder | Owner runs `qodercli login`; confirm allowance and run one smoke before enabling. |
| Qwen Code | Resolve the `qwen3.8-max` HTTP 403 against the account's Token Plan entitlements; set an eligible model in Qwen settings and verify allowance before a smoke. Catalog membership is insufficient. |
| Gemini | Resolve exhausted fetch retries; verify API connectivity, model access and included allowance before a smoke. |
| Other gated CLIs | Confirm included allowance for the configured provider/model or obtain an explicit task credit budget, then one smoke before enabling. |

Never log in, change credentials, or accept paid fallback automatically. A
local headless command does not authorize cloud execution. `devin-cloud`,
`jules`, `cursor-cloud` and `copilot-agent` are refused; no cloud adapter is
implemented. GUI companions remain outside this dispatcher.

## 2. Run one host

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\use-coding-agent\Invoke-CodingAgent.ps1" -HostId devin -PromptFile .\task.txt -Cwd C:\Repos\example
```

Prefer `-PromptFile` for the task text. `-Prompt` is for a short one line
with no quotes. Long, quoted, multiline or shell-sensitive argument prompts
use a temporary UTF-8 file and a short pointer; file/stdin hosts receive the
task directly. Gemini admits that runtime directory with
`--include-directories`. Temporary task files are removed on completion.
`-Cwd` is the task directory; scratch directories are supported. Codex uses
`exec --skip-git-repo-check -` without initializing Git. Antigravity receives
an attached `--print=<prompt>` after its permissions flag.

Every child is windowless. Warp sets child-only `WARP_CLI_MODE=1`; it never
opens the terminal GUI. Claude and Devin inherit their relevant API-key
variable from the User environment only when absent in the process. Values
are never printed. Claude's API route still requires a verified allowance
or an explicit budget. A timeout kills the process tree and exits 4.

Exit 0 means the child exited 0. Exit 2 is a launch failure; an absent
executable found during readiness checking is a refusal (3). Exit 3 also
covers policy, autonomy and input refusals. Native child exits 2–4 are
mapped to 1 to preserve these dispatcher codes; other child codes pass through.
Per-run UTF-8 `.out` / `.err` logs stay under
`%LOCALAPPDATA%\AgentHub\runtime\coding-agent-dispatch`.

`-ShowCommand` prints the file and arguments and does not start a process.

## 3. What the orchestrator owns

Pick the host, write the task, set `-Cwd`, and return the child's output.
Do not restate the child's flags. Do not launch Warp, the Cursor IDE,
Antigravity Desktop, Antigravity IDE, OpenCode Desktop, VS Code, or any
other GUI to get around a refusal.

Claude and Codex also have an orchestrator agent named `coding-agent` that
only runs this script. Use that agent when the host already routes work to
named agents. The script remains the contract either way.

## 4. Final check

- `-List` was the source for "callable", not memory.
- `-Cwd` is the task repository.
- The command was this script, not a hand-built CLI line.
- A refusal was reported as a refusal.
