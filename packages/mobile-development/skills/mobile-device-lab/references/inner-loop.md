# Inner loop

Read when choosing between reload and rebuild, speeding a native build, picking a test tool, or testing a web app on a device.

## Reload, don't rebuild

A Debug simulator build embeds no JavaScript; it fetches it from Metro at runtime. A Release build in the guest takes about 40 minutes.

| Change | Cost |
| --- | --- |
| JavaScript, TypeScript, assets | reload |
| `EXPO_PUBLIC_*` value | restart Metro, reload |
| New native dependency | rebuild |
| App config, config plugin, anything under `ios/` | prebuild and rebuild |

Steps:

1. Sync and build the Debug shell once (`build-expo-simulator.sh ... booted --dev`). A red screen on first launch is expected.
2. Run `mobile.ps1 metro <productId> -ProjectPath <app> -Attach`. It starts Metro on the VMnet8 address, sets `adb reverse`, proves the guest can reach Metro, and opens the dev-client link. Metro runs hidden; read its logs under `%LOCALAPPDATA%\AgentHub\mobile-lab\logs` when bundling fails.
3. Edit on Windows; the app reloads.

## `EXPO_PUBLIC_*` is inlined by Metro

Config must exist on the machine that runs Metro. A Release build in the guest runs Metro there, the sync skips gitignored `.env`, and the build succeeds with those values absent; nothing repairs it afterwards. Prefer Metro on the host. When a Release build is required, run `scripts/Test-MobileLabAppConfig.ps1 -ProjectPath <app>` first (it lists the variables the source reads and whether each is present, never printing values), then carry the file by name: `Sync-RepoToGuest.ps1 ... -IncludeIgnored 'apps/mobile/.env'`. Use explicit repo-relative paths, never globs, because these files hold credentials.

## Cheaper native builds

- React Native core and Hermes ship prebuilt (including x86_64 simulator slices); every `expo-*` and community pod still compiles from source.
- `build-expo-simulator.sh` builds the host architecture only and enables `ccache` when installed in the guest. `--all-archs` and `--no-ccache` reverse that. `--profile` prints per-phase timings; use it before arguing about where time goes.
- Keep `~/Library/Caches/ReactNative`; a clean prebuild otherwise re-downloads 200 MB.
- Never add `expo prebuild --clean` to a warm path. The script prebuilds only when `ios/` is absent.
- If the log says "reverting to building from source", a prebuilt download failed; fix the network and rebuild.
- Debug does not substitute for Release when the subject is startup time, Hermes bytecode or `__DEV__` behavior.

## Web apps on a device

`mobile.ps1 web <productId> -Url <url>` opens Mobile Safari (iOS Simulator) and Chrome (emulator). Only loopback hosts (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) are rewritten: Android uses `10.0.2.2`, the guest uses the Windows VMnet8 address. Any other host opens unchanged. The script checks the port on the VMnet8 address; a dev server bound to `127.0.0.1` is invisible to both devices, so start it with `--host 0.0.0.0` (`vite --host 0.0.0.0`, `next dev -H 0.0.0.0`).

## Which tool

| Question | Tool |
| --- | --- |
| Does this component or logic behave? | Jest + React Native Testing Library |
| Does this flow still work end to end? | Maestro (committed flows) |
| What is this app doing right now? | Appium MCP (this lab) |

A bug found with Appium should leave a Maestro flow behind. Maestro runs natively on Windows (Java 17+, on `PATH`) and drives development builds; `maestro test --continuous` re-runs on change. Maestro cannot drive a physical iPhone locally. Do not adopt Detox: it needs its own instrumented build and has no supported Expo path on this stack.

Testing Library v14 is async: `await render(...)`, `await fireEvent...`, `await act(...)`. An un-awaited `render` returns a Promise that looks like a broken environment. Jest's `expect` takes one argument. A `console.error` can fail a test where `jest.setup.js` throws on it; the cause is usually a missing `await`, so fix the test.
