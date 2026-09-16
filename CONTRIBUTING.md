# Contributing

AgentHub is a host-neutral control plane: portable registry data, one path
binder, and an optional personal overlay. Do not add a second rebase, and
do not put machine identity in git.

## First run

See [docs/development/quickstart.md](./docs/development/quickstart.md).

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
```

Or: `node ./scripts/agenthub-cli.mjs init` then
`node ./scripts/agenthub-cli.mjs validate`.

## Layout

- `packages/` — capability content. Repository-relative `canonicalSource`.
- `registry/` — parity contract. Host destinations are `{userHome}` templates (`/` separators; `{userProfile}` is an alias). OS config roots use `{roamingConfig}` and `{localData}`.
- `scripts/lib/PathBinding.ps1` — the only path materializer.
- `scripts/lib/CapabilityGraph.ps1` — public graph plus overlay.
- `scripts/agenthub-cli.mjs` — thin Node wrapper over `AgentHub.ps1`.
- `overlays/personal.example/` — template for a local private overlay. Not required for public capabilities.
- `overlays/personal/` — this machine's private capability list when present.
- `policy-core.md` — portable policy. `global-agent-policy.md` (when present) is a compiled personal deployment document.
- `agenthub.profile.example.json` — optional local roots. The real `agenthub.profile.json` is gitignored.

## Rules

- Secrets stay in environment variables or the OS credential store. Registry files reference names, never values.
- A `-UserProfile` override must not write the live profile. Do not weaken `tests/Test-SyncInstructions.ps1` or `tests/Test-SyncAgentHubRegistryRoot.ps1`.
- Core must not import `overlays/personal` or a `visibility: private` package as a default dependency.
- Use official host formats. Do not invent a plugin manifest for a host that has none.
- Personal names, local runtime roots, and client document paths belong in the overlay, not in `policy-core.md` or tracked host templates.
- Platforms are Windows, macOS, and Linux. Do not add a second path layout, and do not invent a mobile host path. A `.cmd` / `.exe` / `AppData` pin is Windows-only; do not map it onto `~/Library` or XDG.

## Checks

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\tests\Test-PathBinding.ps1
pwsh -NoProfile -File .\tests\Test-CapabilityOverlay.ps1
pwsh -NoProfile -File .\tests\Test-PublicCoreExport.ps1
```

A public tree is produced by `scripts/Export-PublicCore.ps1` (or
`node ./scripts/agenthub-cli.mjs export <dir>`). That script does not push and does not change
remote visibility. Private package ids come from `visibility: private` in
`registry/capabilities.json`.
