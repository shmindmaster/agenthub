# coding-agent-dispatch

Version 0.2.5 (loose skill; version metadata lives in `SKILL.md`).

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
its registered wrapper supplies `--skip-trust` and the dispatcher uses
`--approval-mode yolo`. `windsurf`
routes to Devin. Readiness is additionally gated by
`dispatchPolicy` and each host's autonomy profile. Devin uses its paid plan
model recorded in `registry/fleet-profile.json`; OpenCode's Go model is
selected there but dispatch remains disabled because no Go-plan account entry
is configured.
Windsurf shares Devin's model and command. Current host readiness is recorded
in `registry/fleet-profile.json`; detailed runtime output stays outside this
public repository.

Account-based authentication is recorded per CLI in `registry/fleet-profile.json`
-> `hostSettings`. Gemini's settings select `oauth-personal`, but the latest
account-mode smoke failed; Gemini remains disabled. The dispatcher removes
host-specific API-key environment variables from account-authenticated
children. OpenCode retains DeepSeek as a secondary provider while awaiting a
Go-plan account entry. Follow the owner-only checklist at
`docs/fleet/account-logins-2026-10-21.md`; do not log in or accept paid fallback
automatically. Other gated CLIs need verified included allowance or an explicit
task credit budget and one smoke before enabling. Model catalogs and help
output alone do not prove working inference.

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
