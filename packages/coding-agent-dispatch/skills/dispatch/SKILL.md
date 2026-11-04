---
name: dispatch
description: Runs a task on another coding-agent host and returns its output. Use when work should go to Codex, Cursor Agent, Gemini, Grok, OpenCode, Devin, Amp, Qoder, Factory Droid, Copilot, Cline or Antigravity, or when asked which hosts can be called.
metadata:
  version: "0.3.0"
---

# Dispatch to another coding agent

`Invoke-CodingAgent.ps1` (in this skill directory) is the only place that knows each host's verified command. Run it; do not build a host CLI line by hand, launch a GUI, or use a subagent that imitates another product.

Deployed path: `%USERPROFILE%/.agents/skills/dispatch/Invoke-CodingAgent.ps1`.

## Steps

1. List callable hosts. Take "callable" from this output, not memory.

   ```powershell
   pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\dispatch\Invoke-CodingAgent.ps1" -List
   ```

   Rows are `id`, `callable|routed|refused`, reason. A refused row stays refused: report it and stop.

2. Write the task to a UTF-8 file and run one host, with `-Cwd` set to the task repository.

   ```powershell
   pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\dispatch\Invoke-CodingAgent.ps1" -HostId <id> -PromptFile .\task.txt -Cwd C:\Repos\example
   ```

   Use `-Prompt` only for a short single line with no quotes. Pass `-TimeoutSec 7200` for program-scale work. `-ShowCommand` prints the command without starting anything.

3. Return the child's output. Do not restate its flags.

Exit codes: 0 child succeeded; 2 launch failure; 3 refusal (policy, autonomy, input, or missing executable); 4 timeout (process tree killed); other child codes pass through, and native 2-4 map to 1. Logs: `%LOCALAPPDATA%/AgentHub/runtime/coding-agent-dispatch/*.out|.err`.

## Rules

- One coding host works at a time. Stop the previous writer before handing a task or session to another host; shared history does not authorize concurrent edits.
- Every child runs windowless and never takes focus. Never open the Cursor IDE, Antigravity, OpenCode Desktop, Warp, VS Code or any GUI to get around a refusal.
- Never run a paid probe or smoke to test availability. Readiness comes from `-List`, the account's included allowance, and `registry/fleet-profile.json` (`dispatchPolicy`, `hostSettings`), which can disable any host with a reason. Help output proves a command contract, not authentication or allowance.
- Never log in, change credentials, or accept a paid fallback automatically. If an auth check fails, keep the host disabled and ask the owner to log in from their own terminal.
- Children use their account login: the dispatcher strips provider API-key variables before launch and never prints values.
- A local headless command does not authorize cloud execution. `devin-cloud`, `jules`, `cursor-cloud` and `copilot-agent` are refused.
- A dispatch does not authorize client access, external messages or deployment.

## Host details

Read `references/hosts.md` when dispatching to Cline, OpenCode, Factory, Devin, Gemini, Warp or Copilot, resuming a Cline session, or auditing a host plugin (`Install-*.ps1`).
