# Task 2 implementation report

## Outcome

Consolidated the package and marketplace identity as `mobile-development`
version `2.0.0`, retained only generic/Claude/Codex manifests, removed the
Cursor/Qoder manifests, and migrated fleet activation and host exposure to the
canonical contract. All active coding hosts are resolved from
`registry/agents.json` plus `registry/capabilities.json#surfaceAliases`; each
canonical mapping exposes both loose skills and catalog discovery. Only Claude
and Codex carry Appium activation, with explicit enable/disable and add/remove
routes and a new-task requirement. Appium remains non-persistent.

The package README is now a concise current-contract view that points to
`registry/mobile-development.json`, `registry/mobile-scope.json`, and
`registry/mcps.json` instead of copying mutable facts. Dated `appium-mcp`
1.92.0 evidence remains only in the ADR and is explicitly historical; current
pin resolution stays in `registry/mcps.json`.

## Files and decisions

- Normalized `packages/mobile-development/plugin.json`,
  `.claude-plugin/plugin.json`, and `.codex-plugin/plugin.json` to
  `mobile-development@2.0.0`; deleted `.cursor-plugin/plugin.json` and
  `.qoder-plugin/plugin.json`.
- Updated both marketplace projections, capability host mappings, native
  activation routes, generated timestamps, current-state documentation, and
  the package content hash.
- Strengthened `tests/Test-MobileDevelopment.ps1` for exact manifest retention,
  marketplace identity, dynamically resolved active-host skills/catalog
  exposure, exact native activation routes, and the external VM README drift
  boundary.
- Reduced `D:\VMs\macOS-Tahoe-AMD\README.md` to the AgentHub/mobile.ps1
  pointer, correct `D:\VMs\macOS-Tahoe-AMD-Backup-2026-08-10` backup, and the
  explicit no-disk/state-mutation boundary. No VMX, VMDK, VMEM, VMSS, NVRAM,
  backup content, or runtime state was changed.

## Verification

- `pwsh -NoProfile -File .\tests\Test-MobileDevelopment.ps1` — **44 passed,
  0 failed**.
- `pwsh -NoProfile -File .\tests\Test-PluginManifests.ps1` — **5 passed,
  0 failed**.
- `pwsh -NoProfile -File .\tests\Test-RegistryContentHash.ps1` — **5 passed,
  0 failed**.
- `pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1` — **PASS: 15
  capability packages, 8 installable plugins, 12 MCP servers, 22 active
  agents**.
- `pwsh -NoProfile -File .\tests\Test-InstalledPluginFreshness.ps1` — **4
  passed, 1 failed**. The remaining content-drift failure is outside Task 2:
  installed copies of product-demo-studio, product-experience-engineering, and
  browser-toolkit differ from their sources. No fleet sync was authorized in
  this task; Task 4 owns synchronization.
- `pwsh -NoProfile -File .\tests\Test-MobileScope.ps1` — **6 passed,
  0 failed**; 21 products classified, 2 frozen, 17 fleet repositories.
- `pwsh -NoProfile -File .\tests\Test-SyncRepoToGuest.ps1` — **4 passed,
  0 failed** using synthetic staged fixtures only; no guest sync ran.
- `pwsh -NoProfile -File .\tests\Test-CapabilityOwnership.ps1` — **5 passed,
  0 failed** across 15 capabilities and 19 managed skill names.
- `pwsh -NoProfile -File .\tests\Test-RegistryHostReferences.ps1` — **5
  passed, 0 failed**.
- `pwsh -NoProfile -File .\tests\Test-DeclaredVsDeployedMcp.ps1` — **104
  passed, 0 failed**.
- `git diff --cached --check` — no whitespace errors.

Computed package content hash:
`727F5E39BFBE86F8BCA1D1B73CC8A018097D82328C0D92150431F7E3C5FA16B1`.

## Base and commit

- BASE: `1081185e4bbbbd0db71e18b0ec0dd9b8e078e78b`
- Task 2 implementation: `46988e0a54ff4397f9de5439a2c23f0b3a29ae6f`
  (`feat: consolidate mobile development fleet packaging`).

No live lab, guest sync, fleet sync, Appium activation, credential operation,
store operation, or external service mutation was performed.

## Fix round 1/5: retired deployed plugin cleanup

### Enumeration and cleanup

- Fix-round BASE: `ec559819688a36da8b94bea9c7f4dae7c2b52067`;
  worktree clean.
- Registry-declared Claude spaces checked: `~/.claude/settings.json`,
  `~/.claude/plugins/installed_plugins.json`,
  `~/.claude/plugins/known_marketplaces.json`, and
  `~/.claude/plugins/cache`. Native `claude plugin list` confirmed the retired
  `mobile-device-lab@agenthub` registration at version 1.1.2, disabled. The
  settings file had one disabled entry, the installed registry had one plugin
  key, and the cache held versions 1.1.1 and 1.1.2.
- Registry-declared Codex spaces checked: `~/.codex/config.toml` and
  `~/.codex/plugins`, plus native `codex plugin list`. Codex had no installed
  registration, config reference, or cache directory for the retired identity;
  its CLI showed only the marketplace row from the not-yet-integrated canonical
  checkout and correctly marked it `not installed`.
- Exact native command:
  `claude plugin uninstall mobile-device-lab@agenthub` — exit 0,
  `Successfully uninstalled plugin: mobile-device-lab (scope: user)`.
  This removed the settings and installed-plugin registrations.
- `claude plugin prune --dry-run` reported `Nothing to prune`; Claude has no
  target-scoped cache-prune command. The exact remaining cache root
  `~/.claude/plugins/cache/agenthub/mobile-device-lab` was therefore validated
  as a non-linked child of the AgentHub cache and moved out of deployed state
  to the recoverable quarantine
  `%LOCALAPPDATA%/AgentHub/quarantine/mobile-device-lab-claude-cache-20260820`.
  It contained 72 files. No unrelated plugin was removed or moved.

### Regression and verification

- Added separate behaviors to `tests/Test-InstalledPluginFreshness.ps1` for
  retired Claude/Codex registration/cache residue and Appium persistence. These
  assertions do not reuse or hide unrelated byte-freshness failures.
- `pwsh -NoProfile -File .\tests\Test-InstalledPluginFreshness.ps1` — new
  retired-identity assertion **PASS**; new persistent-Appium assertion **PASS**;
  overall **6 passed, 1 failed** only because the previously recorded installed
  product-demo-studio, product-experience-engineering, and browser-toolkit
  copies still differ from source.
- `pwsh -NoProfile -File .\tests\Test-MobileDevelopment.ps1` — **44 passed,
  0 failed**.
- `pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1` — **PASS: 15
  capability packages, 8 installable plugins, 12 MCP servers, 22 active
  agents**.
- Post-cleanup native/file evidence: Claude list old identity `False`; Claude
  old cache exists `False`; old registration in Claude settings,
  `installed_plugins.json`, and Codex config all `False`; Appium Node process
  count `0`.

No fleet sync, mobile-development install, Appium enablement, lab start, VM
mutation, or unrelated plugin cleanup was performed.
