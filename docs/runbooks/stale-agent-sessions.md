# Stale coding-agent sessions: find and recycle

Owner direction (2026-10-26): sessions older than seven days are never reused,
because their context is overloaded, so every coding agent's old history is
removed. `scripts/Remove-StaleAgentSessions.ps1` does this on demand. It is
never scheduled: no repeating jobs.

```powershell
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1          # dry run, 7 days
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1 -Apply   # recycle / archive
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1 -Days 14 -Agent grok,gemini-cli
```

Every run writes a JSON manifest (each unit, its last activity, size and
decision) to `%LOCALAPPDATA%\AgentHub\session-cleanup\` unless you pass
`-ManifestPath`. SQLite row backups are written next to it.

## Rules

- A session unit is one session directory, or the files that share a session
  id stem (`<id>.jsonl`, `<id>/`, `<id>.settings.json`). Its last activity is
  the newest write time of anything inside it.
- Files go to the **Windows Recycle Bin**, never a permanent erase.
- A unit is kept if anything in it is newer than the cutoff, if any file is
  held open (exclusive-open probe), or if it contains a protected path:
  Claude `memory\` folders, any `MEMORY.md`, or a `-KeepPath`.
- SQLite row stores are never deleted. When the owning app is not running, the
  rows are backed up to JSON and the app's own archived flag is set
  (`scripts/agent_session_db.py`). When it is running they are skipped.
- Only the session roots below are scanned. Settings, auth, credentials,
  config, skills, plugins and MCP configuration are never touched.

## Where each agent keeps sessions (checked on SH-DESKTOP, 2026-10-26)

| Agent | Session store | Handled as |
| --- | --- | --- |
| Claude Code CLI | `~\.claude\projects\<proj>\<id>.jsonl` + `<id>\`; `file-history`, `session-env`, `shell-snapshots`, `todos`, `debug` | files |
| Claude Desktop | App-managed session list (`%LOCALAPPDATA%\Claude-Data\…\claude-code-sessions`) | archive in the app, not by script |
| Codex | `~\.codex\sessions\YYYY\MM\DD\rollout-*.jsonl`, `archived_sessions\` | files |
| Codex | `~\.codex\state_5.sqlite` `threads.archived` | rows, only while Codex is closed |
| Grok | `~\.grok\sessions\<cwd>\<id>\` | files |
| Cursor | `~\.cursor\projects\*\agent-transcripts`, `agent-tools`; `~\.cursor\chats\*` | files |
| Cursor | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` `composerHeaders.isArchived` | rows, only while Cursor is closed |
| VS Code / Insiders / Cursor / Windsurf (Copilot Chat) | `%APPDATA%\<flavor>\User\workspaceStorage\*\chatSessions`, `chatEditingSessions`; `globalStorage\emptyWindowChatSessions` | files |
| Cline / Roo / Kilo (extension) | `%APPDATA%\<flavor>\User\globalStorage\<ext>\tasks`, `checkpoints` | files |
| Cline CLI | `~\.cline\data\sessions`, `~\.cline\tasks` | files |
| GitHub Copilot CLI | `~\.copilot\session-state\<id>\` | files |
| Factory Droid | `~\.factory\sessions\<cwd>\<id>.jsonl` + `<id>.settings.json` | files |
| OpenCode | `~\.local\share\opencode\opencode.db` `session`/`session_v2.time_archived`; `tool-output\` | rows (closed) / files |
| Gemini CLI | `~\.gemini\tmp\<project>\chats`, `tool-outputs` | files |
| Antigravity | `~\.gemini\antigravity{,-cli,-ide}\conversations`, `brain`, `annotations`, `browser_recordings`, `html_artifacts` | files |
| Windsurf | `~\.codeium\windsurf\cascade`, `brain` | files |
| Amp | `~\.local\share\amp\last-threads` (threads themselves are server-side) | files |
| Qwen Code, Continue | `~\.qwen\tmp\*\chats`, `~\.continue\sessions` | files (absent on SH-DESKTOP) |
| Warp | `%LOCALAPPDATA%\warp\Warp\data\warp.sqlite` `agent_conversations` | not handled: no archived flag, and rows are never deleted |

Codex rows whose rollout file is already gone are invisible in the app; they
are archived on the next run with Codex closed.
