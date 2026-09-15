# Setup

## Requirements

- Windows, macOS, or Linux.
- PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 works for many scripts on Windows only.
- Git.
- Node 18+ optional, for `npx agenthub` / `npm install -g .`.

No package install step is required for the PowerShell lifecycle: this repo is
scripts, registry JSON, and markdown.

## First run

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

See [quickstart.md](./quickstart.md).

## Local-only files (never commit)

- `agenthub.profile.json` — optional path pins (copy from `agenthub.profile.example.json`).
- `overlays/personal/` — private capability list and policy fragment (copy from `overlays/personal.example/`).
- OS local-data AgentHub runtime directory — drift JSON and generated workspaces.
