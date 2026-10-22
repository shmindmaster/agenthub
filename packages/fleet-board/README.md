# fleet-board

Regenerates `FLEET-BOARD.md` — the single-page board of which coding agents are
working for the owner, what rung each task is on, and which owner gates are
waiting.

## Run

```powershell
pwsh -NoProfile -File packages/fleet-board/Regenerate-FleetBoard.ps1
```

Capability-invoked: no scheduled task, no Run key, no auto-start. The script
opens no window. Run it when a refresh is wanted.

## Outputs

- `D:\OneDrive - MahumTech\Documents\06_Research_and_Knowledge_Base\FLEET-BOARD.md`
- A copy at `%LOCALAPPDATA%\AgentHub\runtime\goals\relaunch-2026-10-21\FLEET-BOARD.md`

## Sources

All roots are parameters; defaults are the live fleet paths:

- Program `STATUS.md` files under the goals runtime `programs\*\` and the Codex
  programs root (latest dated heading and its `Rung` line).
- Codex rollouts under `~/.codex/sessions/**/*.jsonl` (first-line
  `session_meta` cwd; last assistant `output_text`).
- Dispatcher `*.out` logs from today (host and start from the filename; the
  dispatcher records no exit-code sidecar, so the board says so).
- `gh pr list --state open` for the fleet repos.
- The heavy-work lease JSON.
- Running coding-host processes with start times.

`-SkipGitHub`, `-SkipProcesses`, and `-SkipMachineState` exist for tests and
partial environments.
