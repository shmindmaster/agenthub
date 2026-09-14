# Setup

## Requirements

- Windows, macOS, or Linux.
- PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 works for many scripts on Windows only.
- Git.
- Node 18+ optional, for `npx agenthub` / `npm install -g .`.

No package install step is required for the PowerShell lifecycle: this repo is
scripts, registry JSON, and markdown.

## First run

Prefer [quickstart.md](./quickstart.md):

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

## This fleet checkout (optional tooling)

- `repowise` CLI (`uv tool install repowise`) for the code-intelligence layer.
  Keep it current with `pwsh -NoProfile -File scripts/Update-RepoWise.ps1 -Apply -RegisterSchedule`.
- Local AI runtimes and document-intelligence roots are private-overlay
  concerns (`local-ai`, `knowledge-access`); they are not required for the
  public core.

## Local-only files (never commit secrets)

- `agenthub.profile.json` — optional path pins (copy from `agenthub.profile.example.json`).
- OS local-data AgentHub runtime directory — drift JSON and generated workspaces.
- In a **public** clone, also keep `overlays/personal/` local (see
  `overlays/personal.example/`). This private fleet checkout may track a
  filled overlay because the remote is private.
