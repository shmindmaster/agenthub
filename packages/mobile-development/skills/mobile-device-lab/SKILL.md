---
name: mobile-device-lab
description: Drives an Android emulator and iOS Simulator through Appium MCP to launch, tap, inspect, screenshot and record. Use when testing or debugging a mobile or responsive web app on an emulator or simulator. Not for Expo, EAS or store work; use mobile-platform-standard.
---

# Mobile device lab

Android runs on this Windows host; iOS runs in the macOS VM, driven remotely. Both use the `appium-mobile` MCP server. Report results as "verified on simulator", never "on device".

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

Hold the lease around anything that mutates a shared emulator or Simulator: build, install, session. An idle probe alone is not permission. Stop if the lease or idle check fails. If Maestro, Xcode or another Appium session is active, wait; never kill another run. Commands: `references/lab-operations.md`.

## 4. Drive

- Android: `appium-mobile:select_device` (android), then `appium-mobile:appium_session_management` create with `remoteServerUrl` omitted (selects the embedded driver).
- iOS: create with `remoteServerUrl` from the `start ios -Json` output; the guest address changes. Capabilities and device name come from `$mobile catalog device.ios-simulator -Json`. Do not set `appium:usePrebuiltWDA` on a first session.
- Prefer `appium-mobile:appium_get_page_source` and accessibility ids over screenshots and XPath.
- Web app in mobile browsers: `$mobile web <productId> -Url <url>`; the dev server must listen on `0.0.0.0`.

## 5. Build, reload and troubleshoot

Reload JavaScript with Metro instead of rebuilding; rebuild only for native changes. Read `references/inner-loop.md` for the app under test. If a guest looks down, check SSH before `vmrun`. Read `references/lab-operations.md` for repair steps.

## References

- `references/inner-loop.md`. Read when choosing rebuild vs reload, building or syncing the app under test, build speed, test tools, or web targets.
- `references/lab-operations.md`. Read for the lease and idle-check commands, a guest that will not start, Gradle builds on this host, guest and Appium setup, WDA, signing certificates, or Maestro on Android.
- `references/physical-iphone.md`. Read when driving the iPhone attached to Windows.
