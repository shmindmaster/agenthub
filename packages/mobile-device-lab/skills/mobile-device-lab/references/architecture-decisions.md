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
boot-entry switching, no alternating workflow.

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
