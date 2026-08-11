---
name: mobile-device-lab
description: Use when driving an Android emulator or iOS Simulator for mobile development, validation, or testing without a physical device — app launch, tap/type, inspection, screenshots, screen recording, and cross-platform comparison.
---

# Mobile device lab

One control plane for both platforms on this machine, with no physical device,
no paid Mac, no cloud device farm, and no subscription.

**Android runs locally on Windows. iOS runs in the macOS VM and is driven
remotely.** Both are reached through the same MCP server, `appium-mcp`.

Read [architecture-decisions.md](./references/architecture-decisions.md) before
changing any version, address, or device name — several obvious-looking
"upgrades" are already recorded there as measured dead ends.

## Which product may you point this at

The lab is product-neutral — it drives whatever build you hand it. Eligibility
is not. Resolve the product against `registry/mobile-scope.json` **before**
driving it, exactly as `mobile-platform-standard` requires:

| Bucket | What this lab may do |
| --- | --- |
| `include` | Drive it. |
| `evaluateLater` | Stop. Native value is unproven, and no mobile identifier may be reserved ahead of that decision. |
| `excludedPendingReposition` | Stop. Identity is frozen. |
| absent | Stop and ask the owner to classify it. Absence never means allowed. |

Driving an existing build does not itself mint an identifier, but the work that
usually follows — creating an Expo or EAS project, a bundle id, a Play package
— does, and that is what the non-`include` buckets forbid.

### Health-sensitive products: the capture tools are the risk

`abacare` and `gentlenext` carry `healthSensitive: true`. This lab's primary
tools are exactly the ones that flag governs:

- `appium_screenshot` and `appium_screen_recording` are screenshot and session
  capture,
- `appium_get_page_source` dumps the full element tree, field values included.

Against those products, run only on **synthetic fixtures**. Never capture a
screenshot, recording, or page source from a build showing real patient data,
and do not persist such artifacts. If you cannot confirm the data is synthetic,
treat it as real and stop.

## Preconditions

Bring the lab up, then verify it. Both are idempotent and safe to re-run:

```powershell
pwsh -NoProfile -File packages/mobile-device-lab/skills/mobile-device-lab/scripts/Start-MobileLab.ps1
pwsh -NoProfile -File packages/mobile-device-lab/skills/mobile-device-lab/scripts/Test-MobileLab.ps1
```

`Start-MobileLab.ps1` boots the emulator and the macOS guest and waits for each.
A host reboot stops both, and nothing else restarts them — Appium itself does
come back inside the guest on its own (verified: guest rebooted, Appium serving
again 170s later, no human action), but only once the guest is running.

`Test-MobileLab.ps1` reports `PASS`/`FAIL` per layer, stops at the first broken
one, and exits non-zero, so it names the layer to fix instead of leaving you to
guess. Add `-SkipIos` to either when only Android is needed — it avoids waking
the VM.

**Do not debug more than one layer at a time.** The gate exists so you don't
have to: emulator, VM, simulator, Appium, and network are checked separately.

## Driving Android — local

Android needs no separate Appium server. `appium-mcp` embeds UiAutomator2 and
talks to `adb` directly.

1. `select_device` with `platform: android`.
2. `appium_session_management` with `action: create`, `platform: android`, and
   **`remoteServerUrl` omitted**. Omitting it is what selects the embedded local
   driver.

## Driving iOS — remote

Never let `appium-mcp` look for a local simulator on Windows; there isn't one.
Go straight to remote mode.

`appium_session_management` with `action: create`, `platform: ios`, and
`remoteServerUrl` set to the guest's Appium URL. Resolve that URL from
`Test-MobileLab.ps1` output rather than typing it — the guest address is
DHCP-assigned and does change.

Standard capabilities for this lab:

```json
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:deviceName": "iPhone 17",
  "appium:platformVersion": "26.5",
  "appium:noReset": true,
  "appium:newCommandTimeout": 600,
  "appium:wdaLaunchTimeout": 900000,
  "appium:wdaConnectionTimeout": 900000
}
```

**Do not set `appium:usePrebuiltWDA` on a first session.** It tells the driver
to skip the build *and install* phase and assume WebDriverAgent is already on
the simulator. Running `build-wda` only builds it into DerivedData — it does not
install it — so the flag produces an endless
`connect ECONNREFUSED 127.0.0.1:8100` retry loop against a device that has no
WDA on it. Confirm with `xcrun simctl listapps booted | grep -i WebDriverAgent`:
if that is empty, the flag is a trap.

Let the driver install WDA once. Only consider the flag afterwards, and only if
`listapps` shows it present.

`iPhone 17` / iOS `26.5` are not preferences — they are the only runtime
installed, and the decision record explains why no older one can be.

## Getting the app under test

The lab drives an app; it does not produce one. This is the step most likely to
block you, so resolve it before creating a session.

**The app must live on the machine running that platform's server.** An
`appium:app` path is resolved by the Appium server, so a Windows path is
meaningless to the guest.

| Platform | Artifact | Where it must be |
| --- | --- | --- |
| Android | `.apk` | Windows, or already installed on the emulator |
| iOS | `.app` for **iphonesimulator** | inside the macOS VM |

An iOS **device** build (`.ipa`, `Debug-iphoneos`) will not run on a simulator.
They are different architectures and different SDKs.

For an Expo product, the simulator build is what an EAS profile with
`ios.simulator: true` produces — the `.tar.gz` archive that is useless on a
phone. It is exactly the right input here.

Install once, then address the app by bundle id instead of shipping a path:

```bash
ssh macvm 'xcrun simctl install booted /Users/maclab/build/MyApp.app'
```

and thereafter use `appium:bundleId`.

## Evidence

For a solo developer this is most of the value — a failure you can watch beats
a failure you have to reproduce.

- `appium_screenshot` — always available.
- `appium_screen_recording` — backed by `ffmpeg` 8.1.2 in the guest.
- `appium_get_page_source` — the element tree; prefer it over screenshots for
  asserting structure, and prefer accessibility ids over XPath for locators.

`mobile: setPermission` is **not** available: `applesimutils` is deliberately
not installed. See the decision record for the reason and the opt-in command.

## This lab is slow, and that is expected

The guest renders in software, so treat these as normal rather than as hangs:

- First run of a freshly installed npm package: **minutes**. Warm: ~8s.
- Appium server cold start: up to ~6 minutes before `/status` answers.
- Simulator cold boot: minutes.

A short timeout here reports a false hang — that mistake has already been made
in this lab. Keep a booted simulator rather than cold-booting per run, and let
`Test-MobileLab.ps1` warm the toolchain before you time anything.

## When not to use this

Use **Maestro** for committed, deterministic regression flows that run in CI
(the fleet standard, run from EAS Workflows). This lab is for interactive,
agent-driven investigation and one-off validation.

The division: Appium MCP is how an agent *investigates*; Maestro is how a
finding becomes a permanent guard. A bug found here should usually leave a
Maestro flow behind.

Nothing here proves real-hardware behaviour. A simulator does not exercise real
GPU, camera, sensors, thermals, or App Store signing. Say "verified on
simulator", never "verified on device".
