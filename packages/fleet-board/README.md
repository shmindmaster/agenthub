# fleet-board

Regenerates a Markdown fleet board from configured local status files,
dispatcher logs, optional Codex session records, and optional GitHub queries.

## Run

```powershell
pwsh -NoProfile -File packages/fleet-board/Regenerate-FleetBoard.ps1
```

Capability-invoked: no scheduled task, no Run key, no auto-start. The script
opens no window. Run it when a refresh is wanted.

## Outputs

- Defaults to `%LOCALAPPDATA%\AgentHub\runtime\fleet-board\FLEET-BOARD.md`.
- Export elsewhere only with the explicit `-BoardExportPath` parameter.

## Sources

Paths and repository scopes are parameters. Defaults are user-local where a
standard root exists; no personal documents or repository names are embedded:

- Program `STATUS.md` files under `%LOCALAPPDATA%\AgentHub\runtime\goals\programs`
  and optional `-CodexProgramsRoot` (latest dated heading and its `Rung` line).
- Codex rollouts under `~/.codex/sessions/**/*.jsonl` (first-line
  `session_meta` cwd; last assistant `output_text`; listed as recent activity,
  not proof a session is still running).
- Dispatcher `*.out` logs completed today (host and start parsed from the
 filename; the dispatcher records no exit-code sidecar).
- `gh pr list --state open` only for repositories passed with `-Repositories`.
- The heavy-work lease only when `-LeasePath` is provided.
- Running processes from the conservative default name list.

`-FleetProfilePath` controls the optional dispatcher-policy source.
`-SkipGitHub`, `-SkipProcesses`, and `-SkipMachineState` support offline tests
and partial environments.
