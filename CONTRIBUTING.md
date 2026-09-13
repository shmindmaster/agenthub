# Contributing

AgentHub is a host-neutral control plane: portable registry data, one path
binder, and an optional personal overlay. Do not add a second rebase, and
do not put machine identity in git.

## Layout

- `packages/` — capability content. Repository-relative `canonicalSource`.
- `registry/` — parity contract. Host destinations are `{userHome}` templates (`/` separators; `{userProfile}` is an alias). OS config roots use `{roamingConfig}` and `{localData}`.
- `scripts/lib/PathBinding.ps1` — the only path materializer.
- `scripts/lib/CapabilityGraph.ps1` — public graph plus overlay.
- `overlays/personal/` — this checkout's private capability list. Not part of a public export.
- `policy-core.md` — portable policy. `global-agent-policy.md` is the compiled personal deployment document.
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

A public tree is produced by `scripts/Export-PublicCore.ps1`. That script does not push and does not change remote visibility.
