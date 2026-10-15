# coding-agent-dispatch

Version 0.2.0 (loose skill; version metadata lives in `SKILL.md`).

Windowless runner so one coding agent can call another. Claude and Codex are
the primary orchestrators. The callable set is whatever
`Invoke-CodingAgent.ps1 -List` prints. Flags are the ones verified against
the installed CLIs on 2026-10-14. A host without that evidence is refused,
including every GUI.

Verified local command contracts: Claude, Codex, Cursor Agent, Qwen Code,
Gemini, Grok, OpenCode, Antigravity CLI, Factory Droid, Cline, Copilot, Amp,
Devin, Qoder and Warp/Oz. `cursor` has a configured alias to Cursor Agent,
currently refused by its interactive autonomy profile; `windsurf` routes
to Devin. Readiness is additionally gated by `dispatchPolicy` and each
host's autonomy profile. Devin (`swe-2-medium`) and OpenCode (`opencode/big-pickle`) passed bounded
live smokes on explicitly free models; the Windsurf alias shares Devin's command.

Cursor Agent needs owner `agent login`; Factory needs owner `/login` inside
`droid`. Qoder needs owner `qodercli login`. Hermes' declared executable is absent. Qwen's configured
`qwen3.8-max` returned 403, and Gemini exhausted transport retries. Other
gated CLIs need verified included allowance or an explicit task credit budget
and one smoke before enabling. Exact owner actions are emitted by `-List`.
Model catalogs and help output alone do not prove working inference.

Codex accepts non-repository working directories without creating Git state.
Antigravity uses attached `--print=<prompt>`. Long or shell-sensitive argument
prompts use temporary UTF-8 task files. Children, including batch shims and
timeout cleanup, run hidden. No cloud adapter, login or scheduled task is
created. Hosted cloud aliases are explicitly refused.

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1 -List
```

Deployment is a separate owner-authorized gate. The skill's targeted command
is `Sync-Capabilities.ps1 -Apply -CapabilityId coding-agent-dispatch`.
Do not use a full `Sync-AgentHub.ps1 -Apply` for this package alone.

`agents/claude/coding-agent.md` and `agents/codex/coding-agent.toml` are the
orchestrator agent definitions. Copy them into `~/.claude/agents` and
`~/.codex/agents`. Sync-Subagents does not own those two files.

`tests/Test-CodingAgentDispatch.ps1` uses synthetic native argument recorders
and never consumes a model run. It covers the command fixes, new hosts,
Unicode/multiline transport, alias policy gates, missing binaries and bounded
hidden process-tree termination. `-DispatcherPath` can demonstrate regression
failures against an older copy without changing installed hosts.
