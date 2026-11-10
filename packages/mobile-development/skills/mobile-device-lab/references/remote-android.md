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
2. Sends `git archive` of `-Ref` (default `HEAD`) to the worker. The worker keeps `node_modules` and `android/` between runs.
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

## Fast reload (not yet working)

A profile with `"variant": "debug"` builds a development client, starts Metro on the worker on port 8081 and reverse-forwards it to the emulator. Measured 2026-11-10 with ABACare's `preview-rig` profile: the build installs and the launcher lists the worker's Metro server, but the app stays on the Expo development launcher, so a committed flow that begins with `launchApp` fails. Until a profile opens the bundle (a development-client deep link before the flow), use release profiles and rebuild; a warm rebuild is about three minutes.

## Move or rebuild the worker

```powershell
pwsh -NoProfile -File $mobile remote provision -HostName <address> -IdentityFile <private key path>
```

`provision` copies `scripts/worker/` to the host and runs `provision-android-worker.sh` as root. It is safe to re-run. The host must be x86_64 Ubuntu with `/dev/kvm`; on AWS that means a nested-virtualization family or a `.metal` size. If the alias already exists, edit its `HostName` in `~/.ssh/config` first.

## iOS

Unchanged: the VMware macOS guest (`ssh macvm`), `eas build --local`, and the Windows lease. See `lab-operations.md`.
