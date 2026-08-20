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

## Fix round 1/5

### Findings addressed

1. `check runtime` now calls a reusable read-only matcher that requires the canonical Android SDK `adb.exe`, an emulator executable under that SDK with the exact registry AVD argument, on-disk AVD configuration matching the registry API, and the authoritative full iOS VMX path. Same-named unrelated AVDs/VMX files cannot report ready.
2. Both loose skills now enumerate `noNative` and state that only an exact `include` record authorizes product-targeted work.
3. The platform skill no longer copies product bundle IDs, the Apple team ID, provider-account topology, or named identity exceptions. It resolves identity from `registry/mobile-scope.json` and treats account facts as live owner-gated state.
4. Executable busy/idle/owned-lease/competing-lease/release coverage is restored in `tests/Test-MobileLabExclusivity.ps1`. Appium cleanup is extracted into the production helper `AppiumSessionCleanup.mjs`, and `tests/Test-AppiumSessionCleanup.mjs` executes success and failure/continue behavior.
5. The canonical contract test now resolves every service invocation and the public wrapper's start/test/sync/metro/web delegate paths, including the guest Appium helper.

### Exact covering verification

- `pwsh -NoProfile -File .\tests\Test-MobileDevelopment.ps1` — **39 passed, 2 failed**. Every Task 1 assertion passed. The two unchanged failures are the already-recorded Task 2 manifest identity/version parity and unsupported Cursor/Qoder manifest removal.
- `pwsh -NoProfile -File .\tests\Test-MobileLabExclusivity.ps1` — **6 passed, 0 failed**: active Maestro rejected, synthetic idle accepted, independent probe blocked by lease, owner probe accepted, competing acquisition rejected, clean release proven.
- `node .\tests\Test-AppiumSessionCleanup.mjs` — **2 passed, 0 failed**: reverse-order deletion/ownership clearing and failure recording with continued deletion attempts.
- `pwsh -NoProfile -File .\tests\Test-MobileScope.ps1` — **6 passed, 0 failed**; 21 products classified, 2 frozen, 17 repos on the repo-standard roster.
- The canonical runtime fixture assertions explicitly produced ready only for the registry AVD/API and exact VMX path, rejected an unrelated AVD, API 35, and `C:\unrelated\macos.vmx`, while the live `check runtime both` process snapshot remained unchanged and reported `startedResources=false`.
- `Test-SyncRepoToGuest.ps1` was not rerun because no sync implementation or test changed in this fix round; its Task 1 checkpoint remains 4 passed, 0 failed.

### Fix-round self-review

- The runtime matcher reads only the Windows process table, AVD config, registries, and VMX; it never invokes adb, emulator, vmrun, SSH, or a guest service.
- Synthetic lease tests redirect `LOCALAPPDATA` to their private fixture and release the named mutex in `finally`.
- Session-cleanup tests execute the same imported helper used by the smoke client and verify cleanup continues after one deletion fails.
- No Task 2 manifest, marketplace document, native connector, fleet deployment, VM state, credential, or external service was modified.
- Fix-round commit is recorded in the parent handoff after commit creation.
