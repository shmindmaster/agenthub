---
name: use-coding-agent
description: Use when a coding agent should run a task on another coding-agent host. Claude and Codex are the primary orchestrators and can call any host this dispatcher lists as callable.
metadata:
  version: "0.2.7"
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

The 0.2.7 contracts cover Claude, Codex, Cursor Agent, Gemini, Grok, OpenCode,
Antigravity CLI, Factory Droid, Cline, Copilot, Amp, Devin and local Warp/Oz.
`registry/fleet-profile.json` -> `dispatchPolicy`
can disable each contract with a reason and owner action. The current verified
model and provider selections are recorded in `registry/fleet-profile.json` ->
`hostSettings` and `dispatchPolicy`. Do not reuse historical free-model
selections for a host whose current policy names a paid plan model.

Account-mode readiness recorded in this repair:

| Host | Status |
| --- | --- |
| Cursor Agent | Account status and a standalone-response smoke passed on 2026-10-22. |
| Amp | Execute mode with dispatch-only MCP servers disabled returned the requested response on 2026-10-22; `amp usage` reported Amp Free. |
| OpenCode | Native 2.1.4 Console account OAuth and exact-response inference through the Go-only endpoint passed on 2026-10-23; no API-key override. |
| Gemini | Dispatcher uses `--approval-mode yolo`; the registered shim skips its yolo default for that explicit invocation and supplies `--skip-trust`. Complete Google OAuth interactively with `gemini` before another smoke. |
| Warp | No supported account-status command or local-only execution mode was verified; keep disabled unless both are established. |
| Other gated CLIs | Confirm included allowance for the configured provider/model or obtain an explicit task credit budget, then one smoke before enabling. |

If a Factory auth check fails, keep dispatch disabled and have the owner run
`droid` and `/login` in their own terminal.

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
opens the terminal GUI. Account-authenticated children use their account login: the provider
API-key variables for Claude, Codex, Cline, Devin, Gemini, Antigravity, Warp,
Grok, Factory, Cursor Agent, Amp and Copilot are removed before launch (owner
rule 2026-10-22). Cline uses the owner's explicitly authorized saved provider
settings for the Alibaba Coding Plan; keys and endpoint configuration remain
in the private Cline profile. OpenCode 2 uses native Console account OAuth
and a privately configured Go-only endpoint. OPENCODE_GO_API_KEY and
OPENCODE_API_KEY are stripped too. Copilot runs on the sh-pendoah GitHub account: the dispatcher reads that
token from gh's keyring into the child environment only. Values are never printed. A timeout kills the process tree and
exits 4. Pass `-TimeoutSec 7200` for program-scale dispatches.

Exit 0 means the child exited 0. Exit 2 is a launch failure; an absent
executable found during readiness checking is a refusal (3). Exit 3 also
covers policy, autonomy and input refusals. Native child exits 2–4 are
mapped to 1 to preserve these dispatcher codes; other child codes pass through.
Per-run UTF-8 `.out` / `.err` logs stay under
`%LOCALAPPDATA%\AgentHub\runtime\coding-agent-dispatch`.

`-ShowCommand` prints the file and arguments and does not start a process.

## Cline session handoff and ACP

For the owner's Qwen `openai-compatible` profile, the optional SDK plugin
`cline/lightweight-chat.js` provides on-demand tool discovery. Its only initial
tool is `find_tools`; each search loads up to five native tools and each user
turn resets the selection. It supplies low reasoning only when no explicit
effort, thinking-off choice or token budget was supplied. Native permissions
and approval behavior are unchanged. The manifest scopes it to `qwen3.8-max`.
CLI and Desktop share the private `~/.cline/plugins/lightweight-chat.js` file;
the VS Code extension is a separate surface.

Audit the installed plugin manually after a Cline update:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.agents\skills\use-coding-agent\Install-ClineToolDiscovery.ps1"
```

Audit exits 1 on missing or changed content. Add `-Apply` to restore the
canonical file and verify its hash. No host is launched or credentials changed.
Application updates normally preserve the user directory, but plugin SDK
compatibility is not guaranteed across future versions. Verify a plain response
and a real discovered file read after an upgrade before claiming compatibility.

Cline CLI 3.0.73 uses normal `--json` execution, the configured provider/model,
low thinking and the same timeout as the dispatcher. This retains native skills,
plugins and MCP. Avoid `--yolo`: its benchmark toolset is a different execution
mode. The existing repo-autonomous policy controls unattended tool approval.

Cline CLI 3.0.73's `--id` resume flag forces interactive mode and cannot be
combined with JSON execution. The dispatcher therefore starts a bounded new
task. To continue existing history, use an ACP client's `session/load` or
Desktop's native session attachment. Both loaded the same synthetic CLI history
successfully on 2026-10-23. Stop the previous writer before handing off and
follow the one-host resource policy. History sharing does not authorize
concurrent edits, client access, external messages or deployment.

Cline also exposes an on-demand stdio ACP agent with `cline --acp`. An ACP
client launches it; it needs no listening network service. Use the absolute
registered executable when PATH differs. The installed CLI passed initialize,
capability negotiation, session creation and history loading on 2026-10-23.
This protocol check did not send a model prompt. A client must handle
permissions; keep `--auto-approve false` unless its specific task authorizes
otherwise. Native ACP is documented at <https://docs.cline.bot/usage/acp>.
Do not invent a Codex ACP client setting or install an A2A/AMCP bridge without
a verified client/server contract. Session resumption is the supported local
coordination route when the orchestrator has no ACP client.

OpenCode 2.1.4 provides native stdio ACP with `opencode acp`. Its private
backend uses the same persisted account and configuration. Protocol 1
initialization, session creation, listing and loading passed a synthetic check
on 2026-10-23 without sending a model prompt. An ACP client owns permission
handling; stop the previous writer before handing off. This does not install
an ACP client into Codex or enable an A2A/AMCP bridge. Native documentation:
<https://dev.opencode.ai/v2/docs/cli/acp/>.

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
