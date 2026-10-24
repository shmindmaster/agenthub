# coding-agent-dispatch

Version 0.2.11 (loose skill; version metadata lives in `SKILL.md`).

Windowless runner so one coding agent can call another. Claude and Codex are
the primary orchestrators. The callable set is whatever
`Invoke-CodingAgent.ps1 -List` prints. Flags are the ones verified against
the installed CLIs on 2026-10-21. A host without that evidence is refused,
including every GUI.

Verified local command contracts: Claude, Codex, Cursor Agent, Gemini, Grok,
OpenCode, Antigravity CLI, Factory Droid, Cline, Copilot, Amp, Devin and
Warp/Oz. `cursor` routes to Cursor Agent; its account-mode smoke returned
`ok` on 2026-10-22. Amp's account-mode smoke returned `ok` with MCP servers
disabled for dispatch. Gemini remains blocked on interactive Google OAuth;
its registered wrapper defaults to `--approval-mode yolo` and `--skip-trust`,
while the dispatcher supplies its explicit approval mode. `windsurf`
routes to Devin. Readiness is additionally gated by
`dispatchPolicy` and each host's autonomy profile. Devin uses its paid plan
model recorded in `registry/fleet-profile.json`; OpenCode's Go model is
selected there. OpenCode 2.1.4 native Console account OAuth and Go-only
inference passed on 2026-10-23 without an API-key override. Its CLI and Desktop
share the native service; `run` uses the child process working directory.
Windsurf shares Devin's model and command. Current host readiness is recorded
in `registry/fleet-profile.json`; detailed runtime output stays outside this
public repository.

Cline uses normal JSON execution with its saved provider/model, low thinking,
native timeout, plugins and MCP rather than the restricted `--yolo` benchmark
toolset. The dispatcher starts bounded new tasks by default. For existing
Cline history, pass `-HostId cline -SessionId <id> -Prompt <task>`; this
uses ACP `session/load` and awaits the new reply. Cline 3.0.73's `--id` is
interactive-only. ACP loading and Desktop attachment previously passed a
synthetic history check. An ACP client launches
`cline --acp` on demand. No A2A bridge, background listener or concurrent writer
is enabled by this capability. The owner's authorized Alibaba Coding Plan
settings stay in the private Cline profile, never in the registry. OpenCode
2.1.4 also passed native ACP initialization and synthetic session creation,
listing and loading. Its on-demand private backend shares persisted account
and configuration; an ACP client is still required for protocol handoff.

`cline/acp-session.mjs` supplies the transport-only resume client: it awaits
`initialize`, `session/load`, then `session/prompt`, collects the new assistant
reply without replayed history, bounds requests, and cancels permission
requests. Its stream tests launch no host. It does not enable Cline dispatch:
the current owner policy permits only Cursor, Grok and Codex agent work.
`cline/acp-dispatch.mjs` connects this client to a windowless, on-demand
`cline --acp --auto-approve false` child. Session and task text travel over
stdin, permissions are cancelled, and only the owned child tree is stopped.
The dispatcher retains its policy and autonomy gates and outer timeout.
Offline tests cover the full dispatcher with a synthetic ACP executable;
live Cline resume remains unverified under the current restriction.

The optional Cline Qwen tool-discovery plugin is maintained in this package's
`skills/use-coding-agent/cline/lightweight-chat.js`. It uses documented SDK
hooks to send only `find_tools` initially, loads a bounded selection when needed,
and resets the selection for each user turn. Native tool implementations and
approval choices remain intact. CLI 3.0.73 and Desktop 0.0.48 passed actual
plain-chat and tool-discovery checks. This is separate from the VS Code extension.
`Install-ClineToolDiscovery.ps1` audits by default; `-Apply` repairs only that
file in the private Cline user directory, with hash readback. AgentHub skill
sync supplies its canonical source and repair command; installation is explicit.
It never starts Cline or registers background maintenance. User configuration
lives outside the application installation and normally survives updates;
future SDK compatibility still requires verification after an upgrade.

OpenCode 2.1.4 has the equivalent native plugin in
`skills/use-coding-agent/opencode/lightweight-chat.js`. It defers tool schemas,
skill descriptions and MCP instructions until `find_tools` selects them, then
resets that selection on each user turn. `Install-OpenCodeToolDiscovery.ps1`
audits by default; `-Apply` installs and verifies the single global plugin file.
It does not change permissions, credentials or the provider. CLI and Desktop
consume the shared service; a running service needs native `opencode reload`
after installation. Test discovery again after an SDK upgrade. Neither repair
command installs a scheduled job. See `docs/fleet/context-reduction.md`.

Account-based authentication is recorded per CLI in `registry/fleet-profile.json`
-> `hostSettings`. Gemini's settings select `oauth-personal`, but the latest
account-mode smoke failed; Gemini remains disabled. The dispatcher removes
host-specific API-key environment variables from account-authenticated
children. OpenCode's private provider settings pin the Go-only endpoint;
Console account OAuth is stored by the native service. Follow the owner-only checklist at
`docs/fleet/account-logins-2026-10-21.md`; do not log in or accept paid fallback
automatically. Other gated CLIs need verified included allowance or an explicit
task credit budget and one smoke before enabling. Model catalogs and help
output alone do not prove working inference.

`-HostId claude -AnthropicApiKey` is a per-call opt-in (owner direction
2026-10-24) that keeps `ANTHROPIC_API_KEY` for that one run while
`dispatchPolicy.claude` stays disabled. It requires
`dispatchPolicy.claude.apiKeyOptIn`, refuses after its `expiresUtc`, passes its
`model` unless `-Model` is given, and is refused for every other host. The key
is shared promotional credit; the skill documents when to use it.

Codex accepts non-repository working directories without creating Git state.
Antigravity uses attached `--print=<prompt>`. Long or shell-sensitive argument
prompts use temporary UTF-8 task files. Children, including batch shims and
timeout cleanup, run hidden. No cloud adapter, login or scheduled task is
created. Hosted cloud aliases are explicitly refused.

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1 -List
```

Deployment is a separate gate. The skill's targeted command is
`Sync-Capabilities.ps1 -Apply -CapabilityId coding-agent-dispatch`; a full
AgentHub deployment uses `Sync-AgentHub.ps1 -Apply -Validate`.

`agents/claude/coding-agent.md` and `agents/codex/coding-agent.toml` are the
orchestrator agent definitions. Copy them into `~/.claude/agents` and
`~/.codex/agents`. Sync-Subagents does not own those two files.

`tests/Test-CodingAgentDispatch.ps1` uses synthetic native argument recorders
and never consumes a model run. It covers the command fixes, new hosts,
Unicode/multiline transport, alias policy gates, missing binaries and bounded
hidden process-tree termination. `-DispatcherPath` can demonstrate regression
failures against an older copy without changing installed hosts.
