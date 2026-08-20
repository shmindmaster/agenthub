# The inner loop

How to get from "I changed a line" to "I can see and assert the new behaviour"
without waiting forty minutes. Read this before doing any mobile work in this
lab; it is the difference between a loop measured in seconds and one measured
in tea breaks.

Everything here is local. No cloud build, no hosted runner, no device farm.

## The one thing to internalise

**A JavaScript change does not need a native build.**

The lab spent months rebuilding a Release binary in the macOS guest for every
change, including changes that were a single line of TypeScript. That is a
~40-minute round trip to test something the bundler could have served in about
a second.

React Native's own build script says so out loud. In
`scripts/react-native-xcode.sh`, a Debug + simulator build prints:

```
Skipping bundling in Debug for the Simulator (since the packager bundles for you)
```

and exits. A Debug build embeds no JavaScript at all; it fetches it from Metro
at runtime. So:

| What changed | What it costs |
| --- | --- |
| JavaScript / TypeScript / assets | reload — seconds |
| A new native dependency | rebuild |
| `app.config.*`, a config plugin, anything under `ios/` | prebuild + rebuild |
| `EXPO_PUBLIC_*` value | restart Metro, then full reload — no rebuild |

That last row is worth its own paragraph.

## `EXPO_PUBLIC_*` is inlined by Metro, not by Xcode

This was misdiagnosed here for a long time, and the wrong diagnosis produced a
wrong fix.

Expo inlines `EXPO_PUBLIC_*` values into the JavaScript bundle at **bundle**
time. The bundler is Metro. Xcode never sees these values.

Consequence: config has to exist on **whichever machine runs Metro**.

- **Release build in the guest** — the guest runs Metro during the build, so
  `.env` must be in the guest. It is gitignored, the repo sync skips gitignored
  files, so it was not. The build then *succeeded* and produced a finished
  binary with those values baked in as absent. ABACare spent ~40 minutes on
  2026-08-17 to be shown its own "BUILD NOT CONFIGURED" screen.
- **Debug build + Metro on the Windows host** — the host runs Metro, `.env` is
  already sitting there next to the source, and the problem does not exist.

The essential property of the first case: it is not a build that fails. It is a
build that succeeds and cannot work, and cannot be repaired afterwards, because
the values are already inlined. Nothing you do post-build fixes it.

Two defences, in order of preference:

1. Run Metro on the host (`Start-MobileLabMetro.ps1`). Best — removes the
   failure mode instead of guarding it.
2. When a Release build is genuinely needed, carry the config across
   explicitly:
   ```powershell
   .\Sync-RepoToGuest.ps1 -RepoPath C:\Repos\shmindmaster\abacare `
     -GuestPath '~/Repos/shmindmaster/abacare' `
     -IncludeIgnored 'apps/mobile/.env'
   ```
   `-IncludeIgnored` takes explicit repo-relative paths, never a glob. These
   files carry credentials; which ones cross the boundary is a decision made by
   name, not by pattern.

And before either, run the check that costs a second instead of forty minutes:

```powershell
.\Test-MobileLabAppConfig.ps1 -ProjectPath C:\Repos\shmindmaster\abacare\apps\mobile
```

It discovers which `EXPO_PUBLIC_*` variables the source actually reads, reports
whether each will be present at build time, and never prints a value.

## The loop

### 1. Build the dev shell once

```powershell
.\Sync-RepoToGuest.ps1 -RepoPath C:\Repos\shmindmaster\<product> -GuestPath '~/Repos/shmindmaster/<product>'
```
```bash
ssh macvm 'bash ~/mobile-lab/build-expo-simulator.sh ~/Repos/shmindmaster/<product> "" booted --dev'
```

`--dev` builds Debug. Expect a red screen on launch — correct and expected, it
has no bundle yet.

### 2. Start Metro on the host and point the app at it

```powershell
.\Start-MobileLabMetro.ps1 -ProjectPath C:\Repos\shmindmaster\<product>\apps\mobile -Attach
```

This resolves the VMnet8 address, starts Metro advertising it, sets up
`adb reverse` for Android, **proves the guest can actually reach Metro**, and
opens the dev-client deep link on the booted simulator.

That reachability proof is not ceremony. A dev server bound to `127.0.0.1` is
perfectly healthy from a host browser and completely invisible to both
simulators, and the symptom is an app that will not load — which reads as an
app bug and gets debugged as one.

### 3. Edit and reload

Edit on Windows. The app reloads. There is no sync step, because Metro is
serving the files being edited.

Rebuild only when the table above says to.

## When you do need a native build, make it cheaper

Measured facts about this stack, as of RN 0.86 / Expo SDK 57:

- **React Native ships precompiled iOS binaries by default since 0.84**, and
  their simulator slices really do include `x86_64` — verified by downloading
  `React.xcframework` and `ReactNativeDependencies.xcframework` from Maven
  Central and reading the `Info.plist`. The Intel guest is *not* forced to
  compile RN core from source. Hermes is likewise downloaded prebuilt.
- So prebuilts were never the problem. **Prebuilts cover React core, its C++
  dependencies, and Hermes — and nothing else.** Every `expo-*` and community
  pod still compiles from source.
- **`ONLY_ACTIVE_ARCH` is set only in the Debug configuration** by the Expo bare
  template. A *Release* simulator build therefore defaults it to `NO` and
  compiles **arm64 and x86_64 for every target and every pod**, and on an
  x86-only host the arm64 half cannot be run by anything. This is the largest
  single lever, and `build-expo-simulator.sh` now sets `ONLY_ACTIVE_ARCH=YES`
  and `ARCHS=$(uname -m)` by default. `--all-archs` restores the old behaviour.
- **ccache is first-party** in this RN line: `react_native_pods.rb` reads
  `USE_CCACHE`, and RN ships its own compiler shims plus a `ccache.conf` whose
  sloppiness settings exist specifically to survive Xcode's index store and
  module maps. The build script enables it when `ccache` is installed
  (`brew install ccache` in the guest). Savings here are **unmeasured** — RN
  and Expo publish no number.
- **Protect `~/Library/Caches/ReactNative`.** It is a shared, SHA1-validated
  tarball cache; without it a clean prebuild re-downloads 200 MB+ over the VM
  network stack.
- **Do not add `expo prebuild --clean` to a warm path.** SDK 57 made prebuild
  clean by default, which regenerates the project and discards target-level
  incrementality. The build script only prebuilds when `ios/` is absent.
- **`--profile`** adds `-showBuildTimingSummary`. Use it before arguing about
  where the time goes; "the build is slow" has at least three causes
  (compilation, codegen script phases, artifact downloads) with entirely
  different fixes.
- **Watch for the silent fallback.** If a prebuilt artifact fails to download,
  RN logs *"reverting to building from source"* and compiles core itself. The
  build still succeeds, just much slower. The build script now surfaces this.

## Testing web apps on a mobile device

The lab is not only for native apps. A web app running as a dev server on
Windows can be viewed and debugged in Mobile Safari on the iOS Simulator and
Chrome on the Android emulator:

```powershell
.\Open-MobileLabWebTarget.ps1 -Url http://localhost:5173/dashboard
```

The hard part is that `localhost` means something different in each target, so
the script rewrites **loopback hosts only**:

| Target | How it reaches the Windows host |
| --- | --- |
| Android emulator | `10.0.2.2` (the emulator's alias for the host) |
| iOS Simulator in the guest | the Windows **VMnet8** adapter address |

`localhost`, `127.0.0.1`, `::1` and `*.localhost` are translated; path, query
and port are preserved. **Any other host is opened unchanged**, which is what
you want when pointing the lab at staging or production — those names already
mean the same thing from every device.

That distinction is load-bearing rather than pedantic. The script originally
rewrote unconditionally, so `-Url https://example.com -Platform android` opened
`https://10.0.2.2/` — this workstation — and reported success. Anyone checking a
deployed site on a device would have been looking at their own dev server.

The most common failure is a dev server bound to `127.0.0.1`, which is
reachable from a Windows browser and from nothing else. The script checks the
port on the VMnet8 address specifically and names the fix
(`vite --host 0.0.0.0`, `next dev -H 0.0.0.0`, and so on) rather than letting
it present as a device problem.

## Which tool for which job

There is real overlap here, and it is worth being deliberate rather than
running everything.

| Tool | Use it for | Notes |
| --- | --- | --- |
| **Appium MCP** | interactive, agent-driven investigation — poke at a running app, read the element tree, try things | Android embedded locally; iOS over `remoteServerUrl` to the guest. WDA compiles on first session. |
| **Maestro** | committed, deterministic regression flows | iOS must run *inside* the guest, because it shells to Xcode tooling — that path is verified. The Windows-native CLI for the Android half is **not installed here** (checked 2026-08-18: nothing on `PATH`, no `~/.maestro`); Java 21 is present, so it is an install away, not a redesign. |
| **Jest + RNTL** | component and logic behaviour | Fastest by a wide margin. See the gotcha below. |
| **Detox** | — | Not viable on this stack. |

Maestro specifics worth knowing, since they change the loop:

- It drives **Expo development builds**, not just Release ones. So E2E flows do
  not require the slow build either.
- `maestro test --continuous` re-runs flows on change.
- `maestro start-device` boots a simulator or emulator directly.
- There is a first-party `maestro mcp` server, which overlaps functionally with
  the Appium MCP for agent-driven use. (`maestro chat` is discontinued.)

Why Detox is out, on four independent grounds: its support matrix stops at RN
0.84 and this stack is on 0.86; `@config-plugins/detox` was deleted from the
Expo monorepo in June 2025 and its npm package is frozen at `expo ^53`; Expo's
Detox guide is a 404; and Detox's own docs say *"There is no special support for
Expo projects in Detox"* and refer you to the Expo community. Both sides point
at each other and one target does not exist. There is no deprecation notice —
the evidence is a commit rate that fell from 971 in 2024 to 41 year-to-date.

## Component testing works — the gotcha that made it look broken

`@testing-library/react-native` v14 made the whole API **asynchronous**.
`render`, `renderHook`, and `fireEvent` return Promises, and `act` must always
be awaited.

Calling `render(...)` without `await` gives you a Promise. `Object.keys()` on it
is `[]`. That looks *exactly* like a broken environment, and it was diagnosed as
one here — component testing was written off, and real logic went untested on
the strength of it. The actual fix is one keyword:

```tsx
import { render, screen } from '@testing-library/react-native';

it('renders and finds text when render is awaited', async () => {
  await render(<View><Text>hello lab</Text></View>);
  expect(screen.getByText('hello lab')).toBeTruthy();
});
```

Two related traps in the same area:

- **`expect(value, message)` is vitest syntax.** Jest's `expect` takes exactly
  one argument, and the second is silently ignored. If a failure needs to name
  something, put it in the test name or the asserted value.
- **A `console.error` may fail the test.** ABACare's `jest.setup.js`
  deliberately throws on any `console.error`, because React reports `act()`
  violations and invalid props through it. When that fires, the test is usually
  missing an `await` — fix the test, do not silence the setup.

## When the guest misbehaves

The guest is the least reliable component in the lab, and its most common
failure is not being down — it is being *reported* as down.

Measured 2026-08-17: the guest had been up 4h13m and was serving SSH and Appium
normally. `vmrun list` said "Total running VMs: 0" and
`vmrun getGuestIPAddress` failed from every shell. The host-to-guest VMX
control channel had degraded while the network was entirely healthy. An hour
went into diagnosing a guest that was fine the whole time.

Both entry points now separate *proposing* an address from *believing* one.
`MobileLabGuest.psm1` collects candidates from four sources — the on-disk cache,
the VMware DHCP lease file, `ssh_config`, and `vmrun` last — and accepts only an
address SSH actually reaches. On the day above, the DHCP lease file held the
correct address the entire time; the resolver now finds it in about 0.2s.

`Test-MobileLab.ps1` no longer gates on `vmrun list` either. If SSH reaches the
guest while `vmrun` claims nothing is running, it says so explicitly and
continues, naming the VMX channel as the degraded component rather than the
guest.

To check by hand:

```powershell
Import-Module .\MobileLabGuest.psm1
Resolve-MobileLabGuestAddress -SkipVmrun    # route around a broken VMX channel
Get-MobileLabLeaseAddresses                 # what VMware's own DHCP handed out
```

## Things this lab still cannot tell you

- **Nothing here proves real-hardware behaviour.** A simulator does not
  exercise real GPU, camera, sensors, thermals, or App Store signing. Say
  "verified on simulator", never "verified on device".
- **Debug is not a substitute for Release** when the subject is startup time,
  Hermes bytecode behaviour, or anything gated on `__DEV__`. Release-only
  faults in this RN line are real and current.
- **The guest has a dated ceiling.** macOS 26 Tahoe is the last macOS
  supporting Intel, and Xcode 27 will not install on Intel at all. The first
  Expo SDK requiring Xcode 27 ends this VM, and no build flag helps — the
  blocker is the Xcode binary's own architecture.
- **Maestro's per-run startup cost against an Appium/WDA session is not
  measured**, here or anywhere published. If that number matters to a decision,
  time it locally rather than reading a comparison page.
