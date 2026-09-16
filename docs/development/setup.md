# Setup

## Requirements

- Windows, macOS, or Linux.
- PowerShell 7.4+ (`pwsh`). Individual scripts may declare a lower compatible
  floor, but the full validation suite and assurance demo require 7.4+.
- Git.
- Node 18+ optional, for `node ./scripts/agenthub-cli.mjs ...`.

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
