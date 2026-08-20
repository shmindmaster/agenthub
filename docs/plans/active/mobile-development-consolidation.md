# Mobile Development Capability Consolidation

## Goal

Create one canonical `mobile-development` capability for the local mobile stack while preserving the active VMware guest, its suspended state, and the known-good backup. The public contract is `packages/mobile-development/mobile.ps1`; mutable facts remain single-sourced in registries or live configuration.

## Global Constraints

- Do not delete or modify either VM disk tree, the suspended-memory state, or the known-good backup. Only the active VM README may change.
- Do not create or mutate Apple, Google, Expo, Firebase, signing, store, production, credential, or external-service state.
- `registry/mobile-scope.json` remains the sole eligibility and identity authority. Product-targeting commands require an `include` product; the fixed synthetic deep-smoke fixture is the only exception.
- `registry/mcps.json` remains the sole Appium MCP package-pin authority. Appium is on-demand for Claude and Codex only and must not persist in host MCP configuration.
- Guest Appium, XCUITest, and simulator expectations live in `registry/mobile-development.json`. Live VM hardware comes from `D:\VMs\macOS-Tahoe-AMD\macos.vmx`.
- All active coding hosts receive the loose skills and catalog. Preserve the skill names `mobile-platform-standard` and `mobile-device-lab`.
- Hyper-V/WHPX is an Android acceleration substrate, not a second mobile lane. WSL2 and Docker are not mobile providers.
- Physical devices, signing, push, deep links, observability, EAS, and store operations remain specialty and explicitly gated.
- Preserve unrelated dirty files in every repository.

## Task 1: Canonical registry, package, CLI, and core validation

Replace split ownership with `packages/mobile-development`, owned by `mobile-quality`. Add `registry/mobile-development.json` with the approved primary/specialty surface, resources, services, and closed task map. Move both recognizable skills into the package. Add `mobile.ps1` as the only documented entrypoint with catalog, scope, read-only file/runtime checks, MCP activation/cleanup, lab start, deep test, sync, metro, and web commands. Reuse existing scripts behind the entrypoint. Resolve pins, eligibility, guest expectations, and live VM hardware from their authorities. Rename and strengthen the mobile test suite to cover pin parity, manifest parity, duplicate ownership/residue, host exposure, Appium persistence, catalog resolution, scope gates including `noNative`, evidence safety, path/VM drift, and read-only behavior.

## Task 2: Fleet packaging, documentation, and VM contract migration

Rename the marketplace/plugin identity to `mobile-development`; retain generic, Claude, and Codex manifests at one version. Remove the old package/deployed-plugin identity and update capability ownership, host mappings, activation routes, registries, hashes, and generated/readme surfaces. Replace the package README with a concise generated current-contract view and retain history/rejected alternatives in the ADR. Reduce the active VM README to a thin AgentHub pointer with the correct backup path and remove stale fixed hardware, IP, boot-entry, and download guidance. Do not touch VM disks or suspend files.

## Task 3: Rexa and ABACare consumer migration

In their isolated worktrees, update the enumerated Rexa scripts, tests, and deployment runbook plus ABACare's Maestro README to call `mobile.ps1`. Preserve unrelated dirty work in the original checkouts. Run Rexa's focused iOS-gate tests and ABACare's documentation check.

## Task 4: Acceptance, fleet synchronization, and live synthetic smoke

Run `Test-MobileScope.ps1`, the expanded mobile-development suite, `Test-SyncRepoToGuest.ps1`, manifest/freshness tests, `Validate-AgentHub.ps1`, and the full AgentHub suite. Audit then apply fleet synchronization; verify old residue is absent, every active coding host can read the catalog, and Claude/Codex can activate and cleanly deactivate Appium. Start the lab and run the leased synthetic Android+iOS deep smoke against the registry pin. Report emulator/Simulator evidence only. Recompute capability hashes and refresh RepoWise after commit.

## Completion Contract

Report changed files, focused and full validation evidence, branch/commits, fleet-sync state, live emulator/Simulator evidence, remaining risks, and the next required gate. Keep implemented, tested, committed, synchronized, and user-validated states distinct.
