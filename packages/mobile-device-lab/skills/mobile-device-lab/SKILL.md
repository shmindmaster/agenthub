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
pwsh -NoProfile -File 'C:\Repos\shmindmaster\agenthub\packages\mobile-device-lab\skills\mobile-device-lab\scripts\Start-MobileLab.ps1' -Json
pwsh -NoProfile -File 'C:\Repos\shmindmaster\agenthub\packages\mobile-device-lab\skills\mobile-device-lab\scripts\Test-MobileLab.ps1' -Json
```

`Start-MobileLab.ps1` boots the emulator and the macOS guest and waits for each.
A startup also deploys the canonical `scripts/guest/*.sh` set as LF-only UTF-8
before polling Appium; if the launch-agent definition changed, it restarts only
Appium and waits for readiness. Do not maintain a second guest-side copy.
A host reboot stops both, and nothing else restarts them — Appium itself does
come back inside the guest on its own (verified: guest rebooted, Appium serving
again 170s later, no human action), but only once the guest is running.

`Test-MobileLab.ps1` reports `PASS`/`FAIL` per layer, stops at the first broken
one, and exits non-zero, so it names the layer to fix instead of leaving you to
guess. Both commands resolve the VMware DHCP address dynamically and emit a
stable JSON final line containing readiness, device/runtime identity, the guest
Appium URL, stage evidence, and remediation. Add `-SkipIos` to either when only
Android is needed — it avoids waking the VM.

For deterministic infrastructure validation, run the deep synthetic smoke:

```powershell
pwsh -NoProfile -File 'C:\Repos\shmindmaster\agenthub\packages\mobile-device-lab\skills\mobile-device-lab\scripts\Test-MobileLab.ps1' -Deep -Json
```

This builds the local-only fixture under `fixtures/smoke-app`, installs and
launches it on both simulators, initializes pinned `appium-mcp@1.92.0`, checks
the tool catalog, keeps concurrent sessions, taps/types, inspects page source,
and captures screenshots. It never creates an Expo/EAS project, store entry,
credential, or product identity.

Deep validation is intentionally foreground-mutating. Before any build,
install, or launch, it enumerates the Windows process table, the macOS guest
process table, and guest Appium sessions. It refuses to run while Maestro,
Xcode, another simulator mutation, or an Appium session is active. Wait for the
reported owner to finish; never terminate another run merely to make the gate
pass. The deep client pins the enumerated `emulator-*` and Simulator UDIDs, so
it cannot select an attached physical device by name or platform alone.
It also holds the machine-wide
`Global\AgentHub.MobileDeviceLab.ForegroundMutation` lease for the entire deep
run and repeats the idle check after building, immediately before Appium may
install or foreground the fixture. Any product task that will mutate a shared
emulator or Simulator must run `Test-MobileLabIdle.ps1 -Json` first and must not
proceed while that foreground lease is reported.
The private guest Appium service enables only Appium 3's
`*:session_discovery` feature so this preflight can inspect active sessions.
After both MCP sessions are deleted, deep validation also retires only the
WebDriverAgent `xcodebuild` child owned by the lab Appium server for the exact
Simulator UDID. Appium stays running, while a stale WDA runner cannot later
foreground the fixture or permanently block the next exclusivity check.

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

### Building the Android APK on this workstation needs `TEMP` redirected

Not optional, and not project-specific — **every** local `gradlew` invocation on
this box fails without it, before doing any work:

```text
java.io.IOException: Unable to establish loopback connection
```

```powershell
$env:TEMP='C:\Temp'; $env:TMP='C:\Temp'
cd <repo>\android
.\gradlew.bat :app:assembleRelease -PreactNativeArchitectures=x86_64
```

The message names the wrong thing. The cause is
`sun.nio.ch.UnixDomainSockets.connect0` returning WSAEINVAL: since JDK 13 the
Windows NIO selector builds its wakeup pipe from an **AF_UNIX socket**, whose
file lives in `%TEMP%`, and this workstation rejects AF_UNIX socket creation
anywhere under `%LOCALAPPDATA%\Temp` — including fresh subdirectories — while
`C:\Temp` and `D:\` work. Every `Selector.open()` in every JVM fails there:
0/20, against 20/20 for `Pipe.open()` and raw TCP loopback. So it breaks the
Gradle client and the daemon independently, and `--no-daemon` does not help
because it still forks one.

**Do not reach for `JDK_JAVA_OPTIONS`.** It fixes Gradle and then breaks the
native build: every JVM prints `NOTE: Picked up JDK_JAVA_OPTIONS` to stderr, the
NDK's CMake configure step parses that output, and `:react-native-screens` and
`:react-native-worklets` fail with the banner *as* the error. Also useless:
`preferIPv4Stack`, the legacy `WindowsSelectorProvider`, `org.gradle.jvmargs`,
`systemProp.*` (both applied after daemon startup), and `GRADLE_OPTS` (client
only). It is **not** the dynamic TCP port range — that was a wrong first
diagnosis that cost hours.

Verified 2026-08-11 on Rexa: `BUILD SUCCESSFUL in 3m 26s`, 50.8 MB APK,
installed and driven on `rexa-api36`. Full write-up in
`%USERPROFILE%\.gradle\gradle.properties`. Drop the redirect once the
Defender/ASR policy behind it is fixed.

**Android Studio is deliberately not installed**, and installing it would add a
second JDK (its bundled JetBrains Runtime) to a box where "which JDK is the
daemon on" is exactly the question the failure above turns on. `sdkmanager` and
`avdmanager` cover SDK and AVD management from the CLI.

### A signed iOS build in the guest needs the WWDR intermediates first

Signing fails on a fresh macOS guest, and the error names the wrong thing:

```
Distribution certificate with fingerprint <hex> hasn't been imported successfully
```

The certificate imported fine. What failed is *validation*. `eas-build` — and
anything else that checks a signing identity — runs

```bash
security find-identity -v -s "(<TEAM_ID>)" <keychain>
```

and `-v` lists only identities whose **chain builds**. A current Apple
distribution certificate chains through **WWDR G3**, and a guest that has never
signed into Xcode does not have it: the intermediates normally arrive with an
Xcode account sign-in. Measured here 2026-08-11, the only WWDR present was the
original one —

```
notBefore=Feb  7 21:48:47 2013 GMT
notAfter =Feb  7 21:48:47 2023 GMT
```

— the CA whose 2023 expiry broke signing industry-wide. So the identity was
imported and then filtered out as unvalidatable, and the tooling reported that
as a failed import.

Fix, into the **login** keychain (user scope — do not touch the system trust
store, and do not alter trust settings; this only makes the chain resolvable):

```bash
for g in G2 G3 G4 G5 G6; do
  curl -fsSL -o "AppleWWDRCA$g.cer" "https://www.apple.com/certificateauthority/AppleWWDRCA$g.cer"
  security import "AppleWWDRCA$g.cer" -k ~/Library/Keychains/login.keychain-db
done
```

Diagnose before assuming it is this — the same message covers several causes:

```bash
security find-certificate -a -c "Apple Worldwide Developer Relations" -p \
  | openssl x509 -noout -subject -dates
```

An expired-only result is the fault above. Note that a plain
`security find-identity -v -p codesigning` returning **0 valid identities** does
not distinguish "no certificate" from "certificate present but unvalidatable" —
check the intermediates before concluding a guest has no credentials.

An iOS **device** build (`.ipa`, `Debug-iphoneos`) will not run on a simulator.
They are different architectures and different SDKs.

For an Expo product, the simulator build is what an EAS profile with
`ios.simulator: true` produces — the `.tar.gz` archive that is useless on a
phone. It is exactly the right input here.

You do not need EAS for it. Build locally in the guest instead — no cloud
queue, no build minutes, and no credentials, because simulator builds are not
code-signed:

```bash
# 1. mirror the working tree into the guest (uncommitted work included;
#    node_modules, ios/ and Pods in the guest are preserved, not re-sent)
pwsh -File 'C:\Repos\shmindmaster\agenthub\packages\mobile-device-lab\skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1' `
  -RepoPath C:\Repos\shmindmaster\<product> -GuestPath '~/Repos/shmindmaster/<product>'

# 2. build Release for the simulator and install it
ssh macvm 'bash ~/mobile-lab/build-expo-simulator.sh ~/Repos/shmindmaster/<product>'
```

`Sync-RepoToGuest.ps1` is owned and versioned by this capability, under
`scripts/` beside `Start-MobileLab.ps1`. It was moved here from the VM lab
folder (`04-Lab-Operations/`) on 2026-08-13, and that lab path is now a
forwarding shim that calls this copy. There is exactly one implementation —
never restore a second one, in either direction. Two copies of a script is how
the Anki exporter silently drifted and shipped a package with zero media, which
is why the lab path forwards rather than duplicates.

The sync intentionally stages the current, including uncommitted, source tree
through a private Git index before it transfers it. That applies the source
repository's Git `text`/`eol` attributes to the archive without modifying the
developer's index or working tree. In particular, a Windows CRLF checkout must
not send CRLF shell scripts to macOS. It refuses paths with non-EOL Git clean
conversions (such as LFS filters) rather than silently transferring a pointer
or another transformed representation. For a local inspection without SSH,
use `-StageOnly -StagePath <empty-directory>`; it retains the normalized
archive and manifest there.

`build-expo-simulator.sh` runs `expo prebuild` when `ios/` is absent, builds
**Release** (a Debug build expects a Metro server and shows a red screen
without one), installs onto the booted simulator, and prints the bundle id.

Then address the app by `appium:bundleId` rather than shipping a path, which
avoids the "path must exist on the server" trap entirely.

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
