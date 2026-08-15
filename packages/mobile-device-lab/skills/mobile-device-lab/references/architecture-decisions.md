# Mobile device lab — architecture decisions

Recorded 2026-08-10 against the live hardware, not against documentation.
Every "rejected" row below was rejected on measured evidence from this machine;
the reasoning is kept so a later session does not re-litigate it or, worse,
silently re-adopt the discarded option.

## The shape

```
WINDOWS 11 HOST                              VMware (D:\VMs\macOS-Tahoe-AMD\macos.vmx)
  agent (any AgentHub host)                    macOS Tahoe 26.6.1, x86_64
    -> appium-mcp 1.92.0  --------------+        Appium 3.6.0  (0.0.0.0:4723)
         |                              |          XCUITest 12.3.1
         | embedded UiAutomator2        |            WebDriverAgent (prebuilt)
         v                              |              iOS 26.5 Simulator
       adb -> Android emulator          |                iPhone 17
       (WHPX accelerated, local)        |
                                        +-- TCP 4723 over VMnet8
                                            192.168.133.1 -> 192.168.133.128
```

One MCP control plane. Android local, iOS remote. That much of the source
recommendation is right and is adopted unchanged.

## Adopted

| Decision | Evidence |
| --- | --- |
| `appium-mcp` as the single control plane | stdio initialize returned protocolVersion `2025-11-25`, serverInfo `MCP Appium` 1.92.0, 31 tools |
| Android emulator native on Windows | `emulator -accel-check` → `WHPX(10.0.26200) is installed and usable`; `adb devices` → `emulator-5554 device` |
| iOS Simulator inside the macOS VM | `xcrun simctl boot "iPhone 17"` → Booted; screenshot renders |
| iOS driven remotely via `remoteServerUrl` | `/status` from Windows → `ready: true` |
| `appium@3.6.0`, `xcuitest@12.3.1` | `appium driver doctor xcuitest` → **0 required fixes** |
| Prebuilt WebDriverAgent | `** TEST BUILD SUCCEEDED **`, `Debug-iphonesimulator`, 3.5 min |
| `ffmpeg` in the guest | 8.1.2 via brew — backs `appium_screen_recording`, i.e. video evidence |
| Appium 3 session discovery on the private guest service | Deep validation must fail closed when another Appium session owns the Simulator. Appium 3 replaced `GET /sessions` with guarded `GET /appium/sessions`, so launchd enables only `*:session_discovery`; the server remains confined to the VMware NAT network. |

## Rejected, with the reason

### Node 22.x standardisation — rejected

The runtimes already satisfy both packages, so this would downgrade two
working installs for nothing:

```
appium@3.6.0      engines.node = ^20.19.0 || ^22.12.0 || >=24.0.0
appium-mcp@1.92.0 engines.node = >=22
Windows           v26.7.0   ✓ satisfies >=22
macOS guest       v24.19.0  ✓ satisfies >=24.0.0
```

### Xcode 16.x + iOS 18.x — rejected, twice over

1. **Impossible here.** This guest is x86_64. Xcode 16.4 is the last pure-x86_64
   build; everything from 26.x on is Universal. Pinning 16.x also drops the
   iOS 26 SDK that Rexa's `expo-glass-effect` requires.
2. **Unnecessary anyway.** The driver's own support table covers what is
   installed: iOS ≥ 26.4 needs driver ≥ 10.23.2, Xcode 26.0–26.6 needs
   ≥ 9.5.0. Installed driver is 12.3.1.

Corollary: `Automation_iPhone_15` / iOS 18.5 cannot be created. The only
runtime present is iOS 26.5, whose devices are the iPhone 17 family. The
standard automation target is **`iPhone 17`**.

### A second host-only NIC — rejected

The guest has one NIC on VMnet8 (NAT) and Windows already reaches it directly:

```
Test-NetConnection 192.168.133.128 -Port 4799
  TcpTestSucceeded : True
  SourceAddress    : 192.168.133.1     <- the VMnet8 host adapter
```

The security rationale for host-only — "traffic never leaves the machine" — is
already satisfied, because VMnet8 is a virtual adapter on this host. Adding a
second NIC would buy nothing and cost a bind-address ambiguity and a VM
power-cycle.

Appium therefore binds `0.0.0.0`, which here means exactly one private NIC plus
loopback. That is deliberately *more* robust than binding the literal IP,
because the address is DHCP-assigned and changes on lease renewal.

### Sequential Android/iOS operation — rejected

All three run at once, verified simultaneously:

```
adb devices  -> emulator-5554  device
ssh macvm    -> macvm-UP
simctl       -> iPhone 17 (Booted)
```

VMware runs on the Windows Hypervisor Platform alongside Hyper-V. No reboot, no
boot-entry switching, no alternating workflow. The macOS guest must keep
`vhv.enable = "FALSE"`: it does not need nested virtualization, and Workstation
cannot expose AMD-V/RVI to the guest while Hyper-V is active. The lab starter
self-repairs this setting before power-on.

### `sudo npm install -g` — rejected

Node in the guest is nvm-managed and user-owned
(`/Users/maclab/.nvm/versions/node/v24.19.0`). `sudo` would either miss nvm's
node entirely or leave root-owned files in the user's tree. Install as the user.

### Dropping Maestro — rejected

The fleet standard (`mobile-platform-standard`) already mandates Maestro for
E2E via EAS Workflows. These are different jobs and both are wanted:

- **Appium MCP** — interactive, agent-driven exploration and one-off validation.
  An agent opens the app, looks, taps, reads, and reports. Nothing is committed.
- **Maestro** — committed, deterministic regression flows that run in CI.

Appium MCP is how an agent *investigates*. Maestro is how a finding becomes a
permanent guard. Adopting one does not displace the other.

### AVD on API 35 — adjusted to API 36

Google Play requires new apps and updates to target Android 16 / API 36 from
**2026-08-31**. `rexa-api36` already exists. Standardise there.

### Maestro under WSL for Android — rejected, measured 2026-08-13

WSL 2 is installed here (Ubuntu 26.04), so this was worth testing rather than
assuming. It is the wrong path.

The socket bridge does work, but only after rebinding the Windows adb server to
all interfaces — a raw adb probe from WSL to the host gateway then returned
`OKAY0015emulator-5554 device`. In the default configuration both routes fail:
`/dev/tcp/172.31.48.1/5037` is closed or filtered because adb binds loopback,
and `/dev/tcp/127.0.0.1/5037` is refused because WSL is in NAT mode.
`localhostForwarding=true` does not cover this direction. WSL also has no JDK
and no adb, so it would need a second Maestro install to reach a worse outcome.

**Adopted instead: run Android E2E from the macOS guest over an SSH reverse
tunnel.** One Maestro install (2.8.0) then covers both platforms, which is the
stated preference and is now measured rather than assumed.

```bash
ssh macvm 'adb kill-server'
ssh -f -N -R 5037:127.0.0.1:5037 macvm
```

With that up, and the Windows adb server left at its default loopback-only bind
(`TCP 127.0.0.1:5037 LISTENING`), the guest sees the emulator and drives it:

```
$ ssh macvm 'adb devices -l'
emulator-5554   device product:sdk_gphone64_x86_64 device:emu64xa

$ maestro --device emulator-5554 test smoke.yaml
Launch app "app.shmindmaster.rexa"... COMPLETED
```

Confirmed from the Windows side by
`topResumedActivity=ActivityRecord{... app.shmindmaster.rexa/.MainActivity}`.
No firewall change and no all-interfaces adb bind are needed.

Two hazards, both of which produced a wrong answer during the spike:

- **Always pass `--device`.** Bare `maestro test` silently prefers the guest's
  booted iOS simulator. It returned a plausible tree containing "Rexa" that was
  the iPhone, not the emulator — a green Android run that never touched
  Android.
- **`ADB_SERVER_SOCKET` and `ANDROID_ADB_SERVER_ADDRESS` configure `adb` but
  not Maestro.** `adb devices` succeeds with them while
  `maestro --device emulator-5554 hierarchy` still reports
  `Device with id emulator-5554 is not connected`. That is why the tunnel is
  required rather than optional.

A `could not connect to TCP port 5554: Connection refused` warning persists —
Maestro probing the emulator *console* port, which was not tunnelled. Flows
pass regardless; `-R 5554:127.0.0.1:5554` should clear it, untested.

## Things the source recommendation did not cover

1. **How the app under test arrives.** The recommendation assumes a `.app`
   exists. For an Expo product it does not, and this is the actual bottleneck —
   see "Getting the app under test" in `SKILL.md`.
2. **Cold-start cost.** First run of a freshly installed 249-module package took
   minutes on this software-rendered guest; warm it is ~8s. Short watchdogs
   report false hangs. Every timeout in this lab is deliberately generous, and
   `Test-MobileLab.ps1` warms the toolchain before timing anything.
3. **The Xcode path is versioned.** `xcodes` installs
   `/Applications/Xcode-26.6.0.app`, not `/Applications/Xcode.app`. A literal
   `/Applications/Xcode.app` test is false on a perfectly good install — this
   already caused a compile step to be silently skipped once. Ask the toolchain
   (`xcodebuild -version`), never the path.
4. **Evidence capture**, which is most of the value of automated testing for a
   solo developer: `ffmpeg` is installed so `appium_screen_recording` works.

## Deliberate gap: applesimutils

Not installed. `brew` refused it:

```
Error: Refusing to load formula wix/brew/applesimutils from untrusted tap wix/brew.
```

It is optional (the doctor lists it under optional fixes) and is only needed for
`mobile: setPermission`. Trusting a third-party tap is a supply-chain decision
for the owner, not something to do silently for a capability nothing currently
uses. Rexa is fully offline and requests no permissions. To opt in:

```bash
ssh macvm 'brew trust wix/brew && brew install applesimutils'
```

Until then, treat programmatic permission-granting as unavailable rather than
assuming it works.
