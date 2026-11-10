# Mobile lab: remote Android worker

Decision recorded 2026-11-10. Owner: `mobile-development` capability (`mobile-quality`). Tracking: SH-4379.

## Decision

Day-to-day Android build and test runs on one Linux host with KVM, driven over SSH by whichever coding agent is working. iOS stays on the existing VMware macOS guest. Expo's paid build service is not part of the routine path.

This extends the existing `mobile-development` capability. It adds one command (`mobile.ps1 remote ...`), one resource (`linux-android-worker`) and one registry section (`registry/mobile-development.json` -> `remoteAndroid`). There is no second control plane.

## Why

- Owner direction 2026-11-10: no Docker or WSL on the PC for builds, dev runs or tests. A Gradle build and an emulator on the PC compete with everything else for RAM.
- Development is driven by coding agents, not a browser IDE. An agent needs a shell on a worker and files back, nothing more.
- Mobile changes are expected to be infrequent, so the lab must cost nothing while idle and need no upkeep.

## Kept and cut from the "Mobile Development Cloud" proposal

| Proposal item | Outcome | Reason |
| --- | --- | --- |
| Linux worker with KVM, headless emulator, native Gradle builds | Kept | The core of the lab. |
| Maestro for framework-independent tests | Kept | Both apps already commit Maestro flows. |
| Screenshots and logs returned as artifacts | Kept | Copied back over SSH to `%LOCALAPPDATA%\AgentHub\mobile-lab\remote-runs`. |
| Per-app `mobile-lab.yaml` | Kept, moved | A profile per app in `remoteAndroid.apps`. App repositories are untouched, and identity still comes only from `mobile-scope.json`. |
| Provider-independent runner | Kept, reduced | One provisioning script and one SSH alias. Moving provider means re-running the script and repointing the alias. |
| Remote view and tap | Kept, simplified | scrcpy through an SSH tunnel. No open port, no web server, no extra service on the worker. |
| Coder workspaces, OpenVSCode, code-server | Cut | Agents use SSH. A web IDE is a second system to patch and secure. |
| Docker and Google Android Emulator Containers | Cut | The emulator runs directly on the host. A container adds a privileged `/dev/kvm` passthrough and an image to maintain for no gain on a single worker. |
| Terraform | Cut | One host. A re-runnable shell script is the whole provisioning story. |
| Woodpecker CI | Cut | The agent that made the change runs the flow. No pipeline server. |
| WebRTC browser view, custom dashboard | Cut | scrcpy covers the need with nothing exposed to the internet. |
| Object storage for artifacts | Cut | Evidence is small and short-lived; it is copied to the PC and removed from the worker with `remote clean`. |
| Phone farm, cloud device farms | Cut | Already out of scope in the closed task map. |
| Remote Apple Silicon Mac, droplet-hosted macOS | Cut | Owner decision: no new Mac infrastructure. `ssh macvm`, `eas build --local` and the existing lease stay as they are. |
| Ephemeral workspaces, authenticated remote Appium, automatic idle shutdown | Cut | A persistent source and build cache makes the second build fast. The emulator is started and stopped by command; no timer or service runs anywhere. |

## Shape

```text
agent on any host
  └─ mobile.ps1 remote run <productId>
       ├─ scope check        registry/mobile-scope.json (include bucket only)
       ├─ lab profile        registry/mobile-development.json -> remoteAndroid.apps
       ├─ source             git archive <commit> | ssh mobile-lab
       └─ worker             /usr/local/bin/mobile-lab (flock lease)
            install → expo prebuild → gradle → adb install → maestro
            → screenshot + logcat + junit → result.json
```

- **Worker**: `/srv/mobile-lab` holds source, caches, AVD and artifacts under the unprivileged user `mobilelab`. Android SDK in `/opt/android-sdk`. No Docker, no systemd unit, no cron entry.
- **Source transfer**: `git archive` of a commit, so the worker holds no Git credentials and no repository history. `-WorkingTree` sends tracked uncommitted changes.
- **Turn-taking**: a file lock on the worker, held for the whole run. A second caller stops and is told who holds it. The local `Global\AgentHub.MobileDeviceLab.ForegroundMutation` mutex still governs the Windows emulator and the macOS guest; it cannot arbitrate callers on other machines.
- **Health-sensitive apps**: a profile for a `healthSensitive` product is refused if any variable points at a non-local address. ABACare builds either unconfigured or against the repository's synthetic preview server running on the worker.
- **Stale native project**: `android/` is regenerated with `expo prebuild --clean` whenever the package manifest, app config, lockfile or public build variables change.

## Hosting

| Period | Host | Cost |
| --- | --- | --- |
| Until 2026-11-30 | Shared DigitalOcean build droplet `sh-build-02` (c-32, tagged `teardown-2026-11-30`) | No added cost; the droplet already runs |
| From 2026-12-01 | An AWS nested-virtualization instance (C8i, M8i or R8i family) or a `.metal` size, started for the work and stopped after | Billed only while running |

Daytona sandboxes are not a target for the emulator until one is shown to expose `/dev/kvm`; that has not been checked.

The owner's 2026-11-10 direction to spend the DigitalOcean credit before it expires does not change this: three c-32 and two c-16 droplets were already running that day, the shared one sat idle, and a dedicated emulator host would add spend without adding capability.

## Verified 2026-11-10

| Check | Result |
| --- | --- |
| Provision from the script on `sh-build-02`, twice | Passed; second run changed only what was new |
| Emulator boots headless with KVM | 52 seconds |
| ABACare: build, install, `smoke-unconfigured.yaml`, screenshot and logs returned | Passed on emulator (171 seconds warm) |
| Rexa on the same worker, no infrastructure change: build, install, `other-screens.yaml`, screenshot and logs returned | Passed on emulator (817 seconds cold, including a 441 MB narration upload) |
| scrcpy stream through the SSH tunnel | Passed without a window (`remote view -Check`); the visible window and tapping were not exercised, to keep the owner's screen free |
| ABACare signed-in synthetic profile (debug build, Metro, preview server) | Not passing: the app stays on the Expo development launcher |

## Limits

- Evidence from this lab is "verified on emulator", never "on device".
- One emulator, one run at a time.
- iOS is unchanged and is not covered here.
- Fast reload through Metro on the worker is not working yet, so each change is a rebuild.
- Gitignored inputs a bundle needs must be listed per app (`extraPaths`); Rexa's narration clips are.
