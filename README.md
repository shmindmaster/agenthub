# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across
coding agents — with drift detection and an optional **personal overlay** for
what should stay private on your machine.

## First five minutes

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) on Windows, macOS, or Linux. Node 18+ is optional for the CLI wrapper.

```bash
# optional wrapper
npm install -g .

npx agenthub init          # local overlay + profile from examples
npx agenthub validate      # registry checks
npx agenthub sync          # read-only drift audit
# npx agenthub sync --apply  # deploy after validate passes
```

Or call PowerShell directly:

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

Full walkthrough: [docs/development/quickstart.md](./docs/development/quickstart.md).

## What this is

- One **desired-state registry** (`registry/`) for capabilities, hosts, and MCPs.
- **Validate → audit → apply** lifecycle (`scripts/AgentHub.ps1`).
- Host destinations as `{userHome}` / `{localData}` / `{roamingConfig}` templates — see [docs/architecture/control-plane-modules.md](./docs/architecture/control-plane-modules.md).
- **Personal overlay** (`overlays/personal.example/` → copy to `overlays/personal/`) for private capability ids and policy fragments. Core never imports those packages by default.
- Portable policy in `policy-core.md`. Machine roots in gitignored `agenthub.profile.json`.

This is not “symlink skills into every tool.” It is a host-neutral parity and policy plane: honest host formats, content-hash validation, and explicit degradation when a host cannot honor a surface.

## Layout

| Path | Role |
| --- | --- |
| `packages/` | Canonical capability content |
| `registry/` | Parity contract |
| `scripts/` | Validate, sync, path binding |
| `overlays/personal.example/` | Template for a local private overlay |
| `policy-core.md` | Portable policy |

Runtime output belongs under the OS local-data root (Windows: `%LOCALAPPDATA%\AgentHub`). Do not commit credentials, customer data, or generated media.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [SECURITY.md](./SECURITY.md).
