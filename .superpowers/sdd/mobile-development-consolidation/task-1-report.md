# Task 1 implementation report

## Summary

Implemented the canonical `mobile-development` capability contract and public PowerShell entrypoint, migrated the recognizable `mobile-platform-standard` and `mobile-device-lab` skills into one package, made the retained lab scripts resolve mobile expectations and the Appium MCP pin from their authoritative registries, and added focused acceptance tests.

This checkpoint does not claim full fleet acceptance or a live deep smoke. It did not start adb, an Android emulator, VMware, the macOS guest, Appium, Metro, or a product repository. It did not mutate VM disks, VM state, credentials, stores, signing, Firebase, Expo/EAS, or any external service.

## Files changed

- Added `registry/mobile-development.json` with the approved 14 primary capabilities, 6 specialty capabilities, 8 resource providers, 5 services, closed decision map, authorities, and synthetic fixture.
- Migrated `packages/mobile-device-lab` to `packages/mobile-development` and moved `mobile-platform-standard` from `packages/portfolio-engineering` into that package.
- Added `packages/mobile-development/MobileDevelopment.psm1` and `packages/mobile-development/mobile.ps1`.
- Updated retained mobile lab scripts and guest helpers to resolve Appium/XCUITest/simulator/Android expectations from the registry.
- Updated `registry/capabilities.json` and `registry/mcps.json` for canonical ownership and recomputed affected content hashes.
- Replaced `tests/Test-MobileLabReachability.ps1` with `tests/Test-MobileDevelopment.ps1` and updated `tests/Test-SyncRepoToGuest.ps1` for the canonical package path.
- Included the controller-authored active plan at `docs/plans/active/mobile-development-consolidation.md`.

## Decisions

- `registry/mobile-scope.json` remains the sole eligibility authority. Product-targeting commands fail closed unless the product is in `include`; the fixed synthetic deep-smoke fixture is the only exception.
- `registry/mcps.json#appium-mobile` remains the sole Appium MCP pin authority. The entrypoint, smoke client, emitted facts, and contract resolve it dynamically.
- VM hardware is parsed live from `D:/VMs/macOS-Tahoe-AMD/macos.vmx`; vCPU and RAM values are not copied into the registry.
- Read-only health checks use file/process inspection only and never invoke adb, emulator, vmrun, or a guest command.
- Existing startup logic now fails closed if nested virtualization is enabled instead of rewriting the VMX.
- Native MCP management uses Claude and Codex management commands and explains that configuration is loaded by a new task.

## Verification

- `pwsh -NoProfile -File .\tests\Test-MobileDevelopment.ps1` — **33 passed, 2 failed**. The remaining failures are Task 2 manifest work: generic/Claude/Codex package identity and version parity, plus removal of unsupported Cursor/Qoder manifests. All other canonical contract, authority, scope, command, read-only, registry-resolution, cleanup, and live-VMX-parsing assertions passed.
- `pwsh -NoProfile -File .\tests\Test-SyncRepoToGuest.ps1` — **4 passed, 0 failed**. Staged archive preserves Git state, normalizes LF, rejects a nonempty destination and non-EOL conversions, and uses an LF-only guest script.
- `pwsh -NoProfile -File .\tests\Test-RegistryContentHash.ps1` — **5 passed, 0 failed**.
- `pwsh -NoProfile -File .\tests\Test-MobileScope.ps1` — **6 passed, 0 failed**; 21 products classified, 2 frozen, 17 repos on the repo-standard roster.
- `git diff --cached --check` — no whitespace errors before the implementation commit.
- JSON parsing of the three modified registries and PowerShell parsing of the entrypoint/module completed without parse errors. An attempted inline `$ErrorActionPreference` assignment was expanded by the outer PowerShell command and printed a non-fatal `Continue=Stop` error; the explicit parses still completed and printed `JSON_AND_PARSE_OK`.

## Self-review

- Confirmed every provider, service command, and file reference in the Task 1 contract resolves.
- Confirmed the exact capability/service/task-map sets and no copied VM hardware values.
- Confirmed scope handling includes `noNative` and all product-targeting routes are include-gated.
- Confirmed read-only checks preserve process tables for adb, emulator, and VMware-related processes.
- Confirmed the deep smoke retains exclusive leasing and session cleanup while using registry-resolved device identifiers and Appium pin.
- Deliberately left Task 2-owned manifests unchanged beyond their package move. Until Task 2 normalizes them, the package is not ready for full validation or fleet deployment.
- Did not run live start/deep smoke, fleet sync, guest sync, marketplace validation, or consumer deployment.

## Commits and base

- BASE: `e64b082e42440dd7bc6096c832b20dac0fce1f21`
- Task 1 implementation: `a3aff59` (`feat: consolidate canonical mobile development capability`)
- This evidence report is committed separately; its commit is reported in the parent handoff.

## Remaining acceptance gaps

Task 2/fix loop owns:

1. Normalize the retained generic, Claude, and Codex manifests to one `mobile-development` identity and version.
2. Remove the unsupported Cursor and Qoder manifests.
3. Complete marketplace/fleet documentation and manifest validation, then rerun the canonical contract test to reach 35/35.
4. Run broader fleet validation after Task 2 lands. Live deep smoke remains a later authorized gate, not part of this checkpoint.
