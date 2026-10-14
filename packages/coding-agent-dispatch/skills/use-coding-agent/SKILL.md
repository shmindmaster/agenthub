---
name: use-coding-agent
description: Use when a coding agent should run a task on another coding-agent host. Claude and Codex are the primary orchestrators and can call any host this dispatcher lists as callable.
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

A row is `id`, `callable|routed|refused`, and a short reason. `cursor` is
routed to `cursor-agent`. Refused rows stay refused. That includes GUI
hosts, interactive hosts, and any CLI whose headless command was not
verified.

## 2. Run one host

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\use-coding-agent\Invoke-CodingAgent.ps1" -HostId codex -PromptFile .\task.txt -Cwd C:\Repos\example
```

Prefer `-PromptFile` for the task text. `-Prompt` is for a short one line
with no quotes. `-Cwd` is the repository the task is about. Do not git init
that directory. The child runs with no window. A timeout kills the process
tree and exits 4.

Exit 0 means the child exited 0. Exit 2 means the executable is absent.
Exit 3 means this script refused the host or the prompt shape.

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
