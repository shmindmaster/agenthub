# AgentHub

Portable control plane for skills, plugins, MCP servers, and policy across coding agents.

- Read `policy-core.md` and `docs/architecture/control-plane-modules.md`.
- Start with `docs/development/quickstart.md`.
- Host destinations are `{userHome}` templates. `scripts/lib/PathBinding.ps1` materializes them for Windows, macOS, and Linux.
- Personal identity and local roots do not belong in this tree. Use `overlays/personal/` (from `overlays/personal.example/`) and a gitignored `agenthub.profile.json`.