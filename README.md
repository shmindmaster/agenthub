# AgentHub — assurance for mixed coding-agent fleets

AgentHub makes capability ownership, policy parity, and configuration drift
inspectable across coding agents. It keeps host-native skills, plugins, MCP
servers, and instructions aligned without pretending every host supports the
same surface.

**Public-good thesis:** agent policy and capability configuration should be portable across hosts while operator-specific identity, paths, and private extensions stay local and user-controlled.

## Where AgentHub fits

AgentHub is not a replacement for an agent package manager. Tools such as
[Microsoft APM](https://github.com/microsoft/apm) and
[AgentStack](https://github.com/Tarekkharsa/agentstack) focus on installing or
rendering portable agent dependencies. AgentHub focuses on the assurance layer
around a mixed fleet:

- one declared owner for each capability;
- explicit `true` / `false` / `null` host-support evidence instead of guessed parity;
- content-hash drift detection between canonical packages and deployed copies;
- policy that can only narrow authority, with local private overlays kept out of public exports;
- validate → audit → apply, where audit is the default and an invalid registry cannot deploy.

The intended interoperability path is to track third-party packages at their
upstream source, let the appropriate installer deliver them, and use AgentHub
to validate ownership, host support, policy, and resulting drift. See
[product positioning](./docs/product/positioning.md).

## First five minutes

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) on Windows, macOS, or Linux. Node 18+ is optional for the CLI wrapper.

The repository is installable from source today. The npm distribution surface
is now bounded and verified, but no npm release should be inferred until a
release appears on the registry.

```bash
# optional wrapper
npm install -g github:shmindmaster/agenthub

agenthub init          # local overlay + profile from examples
agenthub validate      # registry checks
agenthub sync          # read-only drift audit
# agenthub sync --apply  # deploy after validate passes
```

Or call PowerShell directly:

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

## See the assurance loop in 60 seconds

```powershell
npm run demo:assurance
```

The offline demo rejects invalid model output, blocks an unapproved write,
then executes the approved synthetic action in a temporary workspace and
records the observed SHA-256 state. It makes the boundary concrete: **the
model proposes; software decides; the executor acts; evidence records what
happened.** See [`examples/assurance-loop`](./examples/assurance-loop/README.md).

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

See [ROADMAP.md](./ROADMAP.md), [GOVERNANCE.md](./GOVERNANCE.md), [CONTRIBUTING.md](./CONTRIBUTING.md), and [SECURITY.md](./SECURITY.md).
