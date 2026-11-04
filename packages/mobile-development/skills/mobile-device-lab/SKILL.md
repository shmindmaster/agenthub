---
name: mobile-device-lab
description: Drives an Android emulator and iOS Simulator through Appium MCP to launch, tap, inspect, screenshot and record. Use when testing or debugging a mobile or responsive web app on an emulator or simulator. Not for Expo, EAS or store work; use mobile-platform-standard.
---

# Mobile device lab

Android runs on this Windows host; iOS runs in the macOS VM, driven remotely. Both use `appium-mcp`. Report results as "verified on simulator", never "on device".

```powershell
$mobile = "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1"
```

## 1. Resolve the product

Look the product up in `registry/mobile-scope.json` first.

| Bucket | Action |
| --- | --- |
| `include` | Drive it. |
| `noNative` | Stop. No native surface intended. |
| `evaluateLater` | Stop. Reserve no mobile identifier. |
| `excludedPendingReposition` | Stop. Identity is frozen. |
| absent | Stop and ask the owner to classify it. |

Only an exact `include` record authorizes product-targeted lab work; a build, repository, domain or remembered decision is not evidence. Where the product has `healthSensitive`, use synthetic fixtures only. Never capture a screenshot, recording or page source from a build showing real patient data, and never persist one. If you cannot confirm the data is synthetic, treat it as real and stop.

## 2. Start and check

```powershell
pwsh -NoProfile -File $mobile start both -Json              # add -SkipIos to avoid waking the VM
pwsh -NoProfile -File $mobile check runtime both -Deep -Json
pwsh -NoProfile -File $mobile test deep -Json               # synthetic smoke on both platforms
```

The check stops at the first broken layer; fix only that layer. Nothing restarts after a reboot. Cold Appium takes up to 6 minutes, so keep timeouts generous.

## 3. Exclusivity

Hold the lease for the whole build, install and session window of anything that mutates a shared emulator or Simulator; an idle probe alone is not permission. Stop if either step fails. If Maestro, Xcode or another Appium session is active, wait; never kill another run.

```powershell
$root = "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\skills\mobile-device-lab\scripts"
$lease = (& "$root\Enter-MobileLabLease.ps1" -Action Acquire -Json | ConvertFrom-Json)
try {
  & "$root\Test-MobileLabIdle.ps1" -GuestIp <ip> -LeaseId $lease.leaseId -Json
  # builds, installs, sessions
}
finally { & "$root\Enter-MobileLabLease.ps1" -Action Release -LeaseId $lease.leaseId -Json }
```

## 4. Drive

- Android: `select_device` (android), then `appium_session_management` create with `remoteServerUrl` omitted (selects the embedded driver).
- iOS: create with `remoteServerUrl` from the `start ios -Json` output; the guest address changes. Capabilities and device name come from `$mobile catalog device.ios-simulator -Json`. Do not set `appium:usePrebuiltWDA` on a first session.
- Prefer `appium_get_page_source` and accessibility ids over screenshots and XPath.
- Web app in mobile browsers: `$mobile web <productId> -Url <url>`; the dev server must listen on `0.0.0.0`.

## 5. The app under test

The app must sit where its server runs: Android `.apk` on Windows, iOS simulator `.app` inside the VM. Address it by `appium:bundleId`.

For JavaScript changes, never rebuild. Build the Debug shell once, run Metro on the host, then reload:

```powershell
ssh macvm 'bash ~/mobile-lab/build-expo-simulator.sh ~/Repos/shmindmaster/<product> "" booted --dev'
pwsh -NoProfile -File $mobile metro <productId> -ProjectPath <repo>\apps\mobile -Attach
```

Rebuild only for a new native dependency, an app config or plugin change, or edits under `ios/`. Before a Release build of an Expo product, run `scripts/Test-MobileLabAppConfig.ps1 -ProjectPath <app>`: a missing `EXPO_PUBLIC_*` value gives a build that succeeds and cannot work. Sync with `$mobile sync <productId> -RepoPath <repo> -GuestPath <guest-path>`; `-IncludeIgnored` takes explicit file paths, never globs.

## 6. When it breaks

- "Guest down" is usually a degraded `vmrun list`, not a dead guest. Check SSH first.
- `vmrun start` reporting `Unknown error` means a stopped VMware service (`VMAuthdService`, `VMnetDHCP`, `VMware NAT Service`). From an elevated shell, only when startup names stopped services: `$mobile start ios -RepairVmwareServices -Json`. It never self-elevates.

## References

- `references/inner-loop.md`. Read when choosing rebuild vs reload, build speed, test tools, or web targets.
- `references/lab-operations.md`. Read for Gradle builds on this host, guest and Appium setup, WDA, signing certificates, or Maestro on Android.
- `references/physical-iphone.md`. Read when driving the iPhone attached to Windows.
