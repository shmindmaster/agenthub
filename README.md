# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across
coding agents — with drift detection and an optional **personal overlay** for
what should stay private on your machine.

## First five minutes

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) on Windows, macOS, or Linux. Node 18+ is optional for the CLI wrapper.

```bash
npm install -g .           # optional
npx agenthub init          # local overlay + profile from examples
npx agenthub validate
npx agenthub sync          # read-only drift audit
# npx agenthub sync --apply
```

Or:

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

Walkthrough: [docs/development/quickstart.md](./docs/development/quickstart.md).

## What this is

- One **desired-state registry** (`registry/`) for capabilities, hosts, and MCPs.
- **Validate → audit → apply** (`scripts/AgentHub.ps1` / `npx agenthub`).
- Host destinations as `{userHome}` / `{localData}` / `{roamingConfig}` templates — [docs/architecture/control-plane-modules.md](./docs/architecture/control-plane-modules.md).
- **Personal overlay** (`overlays/personal.example/` → `overlays/personal/`) for private capability ids. Core never imports those packages by default. `AGENTHUB_OVERLAY=off` loads the public graph only.
- Portable policy in `policy-core.md`. Machine roots in gitignored `agenthub.profile.json`.

This is a host-neutral parity and policy plane — not only “sync files into every tool.”

## Source of truth

- `packages/<name>/` — canonical capability content.
- `registry/capabilities.json` — ownership and host exposure (`visibility: private` stays behind the overlay).
- `registry/mcps.json` — shared MCPs via env/OAuth references, never credential values.
- `registry/agents.json` — host-native paths as portable templates.
- `.agents/plugins/marketplace.json` — local plugin catalog; `.claude-plugin/marketplace.json` is the Claude-compatible projection.

Runtime output belongs under the OS local-data root (`%LOCALAPPDATA%\AgentHub` on Windows). Do not commit credentials, customer data, or generated media.

## This checkout (private fleet)

This repository may also carry a filled `overlays/personal/` and compiled
`global-agent-policy.md`. Those are not part of a public-core export.

**Public tree:** [github.com/shmindmaster/agenthub-core](https://github.com/shmindmaster/agenthub-core)

Refresh a local export with:

```powershell
pwsh -NoProfile -File .\scripts\Export-PublicCore.ps1 -Destination <empty-dir>
# or: npx agenthub export <empty-dir>
```

The export does not push and does not change remote visibility.

## Commands

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
```

## Documentation

Curated knowledge: [`docs/`](./docs/README.md). Contributing: [`CONTRIBUTING.md`](./CONTRIBUTING.md).
