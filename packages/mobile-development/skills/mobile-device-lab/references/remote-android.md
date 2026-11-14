Read this when building, running or testing an Android app without loading this PC, or when the owner wants to look at a running app.

# Remote Android worker

One Linux host with KVM runs the emulator and the Gradle build. Reach it with the SSH alias `mobile-lab`. Host, AVD and app profiles are in `registry/mobile-development.json` -> `remoteAndroid`. Decision record: `docs/architecture/mobile-lab-remote-android.md`.

```powershell
$mobile = "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1"
pwsh -NoProfile -File $mobile remote status -Json
pwsh -NoProfile -File $mobile remote run abacare -Json          # default profile
pwsh -NoProfile -File $mobile remote run rexa -WorkingTree -Json # include tracked uncommitted changes
pwsh -NoProfile -File $mobile remote start                       # boot the emulator (about a minute); installed apps persist
pwsh -NoProfile -File $mobile remote view                        # owner: see and tap the emulator
pwsh -NoProfile -File $mobile remote stop                        # stop the emulator when done
```

## What `run` does

1. Refuses a product that is not in the `include` bucket of `mobile-scope.json` or has no lab profile.
2. Sends `git archive` of `-Ref` (default `HEAD`) to the worker in 8 MB chunks, each over its own SSH connection with retry (Windows OpenSSH resets bulk streams on some hosts); the worker reassembles them. The worker keeps `node_modules` and `android/` between runs.
3. On the worker, under a lock: install dependencies, `expo prebuild` when inputs changed, Gradle build for x86_64, install on `emulator-5554`, run the profile's Maestro flow.
4. Copies `result.json`, `maestro.log`, JUnit XML, `logcat.txt`, build logs and `screen.png` to `%LOCALAPPDATA%\AgentHub\mobile-lab\remote-runs\<productId>\<runId>`.

Exit code 0 means the flow passed. Report the verdict as "verified on emulator".

## Rules

- The lock belongs to the run that holds it. If `run` reports the lab is in use, wait or pass `-LeaseWaitSeconds`; never stop another run.
- A `healthSensitive` product runs only unconfigured or against a synthetic server on the worker. Do not add a profile that points at a deployed API.
- Run long builds in the background. A first build takes many minutes; a rebuild is much faster.
- Remove an app's source, build output and artifacts when its work ends: `remote clean <productId>`. The host is shared.
- Never run `eas build` as a substitute. A paid build needs owner approval.

## Register another app

Add an entry to `remoteAndroid.apps` with `productId`, the dependency `install` command and at least one profile (`variant`, `env`, `flow`, `screenshot`). The product must already be in the `include` bucket with a recorded `androidPackage`. No worker change is needed.

If the bundle needs gitignored inputs (Rexa's `assets/narration`), list them in `extraPaths`. They are sent once and again only when a file name, size or write time changes.

## Measured on 2026-11-10 (32 vCPU worker)

| Step | Time |
| --- | --- |
| Provision a fresh host | about 4 minutes |
| Emulator cold boot | 52 seconds |
| ABACare release run, warm caches | 171 seconds |
| Rexa release run, cold, including a 441 MB narration upload | 817 seconds |

A cold release build fails with the generated project's 512 MB Metaspace cap; the worker's user-level `gradle.properties` raises it.

## Fast reload (development-client profiles)

A profile with `"variant": "debug"` builds a development client, starts Metro on the worker on port 8081 (`expo start --dev-client`) and reverse-forwards it to the emulator. Before starting, `metro_stop` kills the previous Metro and waits until port 8081 is actually released: pkill is asynchronous, and Expo refuses to start while the dying process still holds the port. A development client stops on the Expo development launcher until a deep link names the Metro server, and every `launchApp` that clears state forgets it again. A profile therefore carries `"launchUrl"` — the app's development-client deep link with the worker's Metro URL in `url=` (for ABACare: `exp+abacare://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A8081`). The worker runs `prepare-flow.mjs` to copy the committed flow beside the original (flows reference scripts relative to their own directory) with a settle wait for the Expo dev launcher's home screen and `- openLink: "<launchUrl>"` inserted after every `launchApp` block, and Maestro runs the copy; the committed flow is never changed. The settle wait matters: a deep link sent while the dev client is still creating its activity is dropped, and the launcher home wins. The worker also pre-compiles the Metro bundle once through Expo's manifest protocol, so the flow's first wait is not spent on a cold transform. A profile may also carry `flowRewrite`, a map of literal address replacements applied to the copy before insertion: Maestro's `runScript` runs on the worker, not in the emulator, so host-side scripts need the worker's loopback (ABACare maps the flow's committed `http://10.0.2.2:8787` to `http://127.0.0.1:8788`, the port its rig actually listens on) while the app keeps the emulator alias. Rewrite targets are fenced to the worker for health-sensitive apps, like profile env. The ABACare rig listens on 8788 (`PORT` in `preCommand`) because the lab host is shared and 8787 is held by another service; a `preCommand` that dies right after start fails the run instead of letting the flow talk to whatever else holds the port. The rig's `launchUrl` also carries `disableOnboarding=1&disableFab=1&disableAutoLaunch=1`: expo-dev-menu's `showsAtLaunch` preference defaults to true, so after every `clearState` launch the dev menu opens over the app unless `disableAutoLaunch` turns it off; expo-dev-launcher reads the flags from the link on every open. This is the Android counterpart of ABACare's `apps/mobile/scripts/ios/guest-journeys.sh`. For a health-sensitive app the embedded Metro URL must be the worker itself (`10.0.2.2`, `127.0.0.1` or `localhost`), the same fence as the profile env.

History: measured 2026-11-10 without `launchUrl`, the build installed and the launcher listed the worker's Metro server, but the app stayed on the Expo development launcher and every committed flow failed (SH-4390). `launchUrl` and the flow copy are the fix.

## Move or rebuild the worker

```powershell
pwsh -NoProfile -File $mobile remote provision -HostName <address> -IdentityFile <private key path>
```

`provision` copies `scripts/worker/` to the host and runs `provision-android-worker.sh` as root. It is safe to re-run. The host must be x86_64 Ubuntu with `/dev/kvm`; on AWS that means a nested-virtualization family or a `.metal` size. If the alias already exists, edit its `HostName` in `~/.ssh/config` first.

## iOS

Unchanged: the VMware macOS guest (`ssh macvm`), `eas build --local`, and the Windows lease. See `lab-operations.md`.
