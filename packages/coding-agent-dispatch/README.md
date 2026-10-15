# coding-agent-dispatch

Windowless runner so one coding agent can call another. Claude and Codex are
the primary orchestrators. The callable set is whatever
`Invoke-CodingAgent.ps1 -List` prints. Flags are the ones verified against
the installed CLIs on 2026-10-14. A host without that evidence is refused,
including every GUI.

Qoder CLI 1.0.45 is verified for `--print --permission-mode auto --cwd`.
It uses the model configured in the user's settings, without a per-call model
override. Authentication and model availability are checked separately from
the dispatch contract. Configuration reference: https://docs.qoder.com/cli/settings.

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1 -List
```

The skill deploys with `Sync-Capabilities.ps1 -Apply -CapabilityId coding-agent-dispatch`.
Do not use a full `Sync-AgentHub.ps1 -Apply` for this package alone.

`agents/claude/coding-agent.md` and `agents/codex/coding-agent.toml` are the
orchestrator agent definitions. Copy them into `~/.claude/agents` and
`~/.codex/agents`. Sync-Subagents does not own those two files.
