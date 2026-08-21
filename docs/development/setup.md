# Setup

## Requirements

- Windows, PowerShell 5.1+ (`powershell.exe`) or PowerShell 7+ (`pwsh`).
- Git.
- `repowise` CLI (`uv tool install repowise`) for the code-intelligence layer.
  Keep it current with `pwsh -NoProfile -File scripts/Update-RepoWise.ps1 -Apply -RegisterSchedule`.

No package install step: this repo is scripts, registry JSON, and markdown.

## First run

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
```

## Related machine state (never committed)

- `%LOCALAPPDATA%\AgentHub` — runtime output, drift JSON, external workspaces.
- `D:\Local-AI` — local AI runtimes, models, caches.
- `C:\Repos\.repowise-workspace.yaml` — RepoWise workspace membership for
  git repos under `C:\Repos\shmindmaster`, `C:\Repos\sh-pendoah`,
  `C:\Repos\musa-dev-team`, and `C:\Repos\pendoah`. Per-repo indexes live in
  each repo's `.repowise/` directory.
