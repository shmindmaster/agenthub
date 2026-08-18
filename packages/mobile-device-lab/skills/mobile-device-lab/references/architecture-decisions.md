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

## Release-by-default as the development loop — rejected, 2026-08-18

`build-expo-simulator.sh` built Release only, and its comment justified that
with "a Debug build expects a Metro server and shows a red screen without one."
True, and the wrong conclusion: needing Metro is the *feature*, not the defect.

React Native's `scripts/react-native-xcode.sh` short-circuits for Debug +
simulator — "Skipping bundling in Debug for the Simulator (since the packager
bundles for you)" — so a Debug build skips Metro bundling and the hermesc
bytecode pass entirely, and carries no embedded JS. The app fetches JS at
runtime, which makes every subsequent JavaScript change a reload rather than a
~40-minute rebuild.

Release stays the **default**, because an automated regression run needs a
binary that stands alone. Debug is now available via `--dev` and is the correct
choice for development. Both are supported rather than one being blessed.

## `ONLY_ACTIVE_ARCH` left at its default — rejected

The Expo bare template sets `ONLY_ACTIVE_ARCH = YES` in the **Debug**
configuration only. Release does not set it, so it defaults to `NO`, and a
Release *simulator* build compiles arm64 **and** x86_64 for every app target
and every pod. On this Intel guest the arm64 half cannot be run by anything.

The build script now passes `ONLY_ACTIVE_ARCH=YES` and `ARCHS=$(uname -m)`;
`--all-archs` restores the old behaviour.

Worth recording what this is *not*: it is not the prebuilt-artifact question.
React Native has shipped precompiled iOS binaries by default since 0.84, and
their simulator slices genuinely include x86_64 — confirmed by downloading
`React.xcframework` and `ReactNativeDependencies.xcframework` from Maven
Central and reading the `Info.plist` (`ios-arm64_x86_64-simulator` →
`arm64, x86_64`). Hermes is likewise downloaded prebuilt, from a separate Maven
group. The Intel guest was never compiling React core from source. What it was
doing is compiling every `expo-*` and community pod from source, twice.

(`HERMES_ENGINE_NO_SOURCE_BUILD` appears nowhere in the React Native repo.
Folklore — do not add it.)

## A single source for the guest address — rejected, measured 2026-08-17

`vmrun getGuestIPAddress` was the only source, polled blindly until timeout.

That day the guest had been up 4h13m and was serving SSH and Appium normally,
while `vmrun list` reported "Total running VMs: 0" and `getGuestIPAddress`
failed from every shell. The host-to-guest VMX control channel had degraded
while the network was entirely healthy. Nothing could recover, because the only
question being asked was of the one component that was broken — and its wrong
answer was indistinguishable from a guest that was not running. An hour went
into diagnosing a guest that was fine.

`MobileLabGuest.psm1` now separates *proposing* an address from *believing*
one: candidates come from an on-disk cache, `C:\ProgramData\VMware\vmnetdhcp.leases`,
`ssh_config`, and `vmrun` last, and only an address SSH actually reaches is
accepted. The lease file held the correct address the whole time; the resolver
finds it in ~0.2s.

`Test-MobileLab.ps1` also stopped gating on `vmrun list`. When SSH reaches the
guest and `vmrun` claims nothing runs, it reports the VMX channel as degraded
and continues, rather than stopping at stage one and naming the wrong
component.

The cache is deliberately **not** an authority — it is probed like every other
candidate and written only after a probe succeeds, so a stale entry costs one
failed probe and nothing else.

## Excluding gitignored files unconditionally from the guest sync — adjusted

The sync payload is `git ls-files -co --exclude-standard`, which is right for
`node_modules` and generated native folders. It was never a decision about
`.env`; that file fell out of a rule written to keep the payload small.

The consequence was invisible until a build proved it. Expo inlines
`EXPO_PUBLIC_*` at **bundle** time, and for a Release build the bundler runs in
the guest — so a guest without `.env` produces a *finished* binary with those
values baked in as absent. Not a build that fails; a build that succeeds and
cannot work, unrepairable afterwards. ABACare spent ~40 minutes on 2026-08-17
to be shown its own "BUILD NOT CONFIGURED" screen.

`-IncludeIgnored` now takes **explicit repo-relative paths**, never a glob. A
pattern like `.env*` would sweep up `.env.production` the first time someone
created one, and these files carry credentials, so which ones cross the
boundary is a decision made by name. The script refuses a named path that does
not exist rather than skipping it silently — a silently-absent config file
reproduces exactly the failure this exists to prevent.

The better fix, where it applies, is to not need it: run Metro on the Windows
host (`Start-MobileLabMetro.ps1`) and `.env` is read from where it already is.

## Detox — rejected on the merits, 2026-08-18

Distinct from the earlier "Dropping Maestro — rejected" entry: this is about
never adopting Detox in the first place. Four independent grounds, each checked:

- its supported range stops at RN 0.84; this stack is on 0.86
- `@config-plugins/detox` was deleted from the Expo monorepo (2025-06-03) and
  its npm package is frozen at `peerDependencies: {"expo": "^53"}`
- Expo's Detox guide (`/build-reference/e2e-tests/`) is a 404
- Detox's own docs: "There is no special support for Expo projects in Detox…
  you should contact the Expo team or the Expo community"

Both projects point at each other and one target does not exist. There is no
deprecation notice and the repo is not archived — the evidence is a commit rate
that fell 971 (2024) → 450 (2025) → 41 (2026 YTD). Architecturally it is also
the wrong shape here: Detox requires its own instrumented native build, which
is precisely what the reload loop exists to avoid.

## Component testing declared impossible — retracted, 2026-08-18

Recorded because the wrong belief was expensive and could easily recur.

`@testing-library/react-native` v14 made the API **asynchronous**: `render`,
`renderHook` and `fireEvent` return Promises. Calling `render(...)` without
`await` yields a Promise whose `Object.keys()` is `[]` — which reads exactly
like a broken environment, and was diagnosed as one. Component testing was
written off across a full session, and clinically load-bearing logic went
untested on the strength of it.

It works. `await render(...)` passes in ~344ms, and 23 tests covering interval
auto-scoring landed immediately afterwards.

Two adjacent traps in the same area:

- `expect(value, message)` is **vitest** syntax; jest's `expect` takes one
  argument and silently ignores the second.
- A `console.error` may fail the test outright where a repo's `jest.setup.js`
  throws on it (ABACare's does, deliberately). React reports `act()` violations
  through `console.error`, so that failure usually means a missing `await` —
  fix the test, do not weaken the setup.

The general lesson is the one this file keeps relearning: an empty result is
not evidence of a broken environment until you have checked what type of thing
you are holding.
