# macOS VM on sh-forge

Until 2026-12-01 iOS builds, Simulator runs and Xcode work run in the macOS VM on sh-forge: container `macos`, compose file `/opt/macos/compose.yml`. When it runs, it holds 32 GB of RAM and 16 cores of the 64 GB, 32-core droplet, so it starts only when work needs it and stops by itself afterwards. The local VMware VM is retired (`Invoke-MobileLabVmrunStart` refuses).

## Use it

The command is `mac` on forge, installed at `/usr/local/bin/mac`; the canonical copy is `../forge/mac`.

```powershell
ssh forge mac run 'xcodebuild -version'   # starts the VM if needed, runs one command in the guest
ssh -t forge mac shell                     # interactive guest shell
ssh forge-mac                              # plain SSH to the guest; the alias starts the VM through `mac proxy`
ssh forge mac status                       # container state, leases, SSH readiness, storage
```

- Each `run`, `shell` or `forge-mac` connection holds a lease while it is open. The VM stops 15 minutes after the last lease ends (`MAC_IDLE_MIN` on forge changes this). A series of commands therefore reuses one boot, which takes about 2 minutes.
- Keep the connection open for the length of the job. A job detached inside the guest (`nohup`, `launchctl`) holds no lease, and the VM can stop under it. Run long builds through `mac run` in the foreground.
- `mac up --keep` keeps the VM up with no lease, for example while the owner installs macOS in the web viewer. Always end it with `ssh forge mac down`.
- Never `docker start macos`, `docker compose up` or `docker restart` it directly: those bypass the leases and nothing stops the VM.
- `mac down` refuses while another lease is active. Never `--force` over someone else's run.

## When it will not start

A cold boot requires Linux `MemAvailable` to cover the configured guest RAM plus 8 GiB of host headroom (40 GiB for a 32 GiB guest). If capacity is short, `mac` exits with status 75 and reports the available and required memory. Retry after current work finishes. Connections to the running guest reuse its existing allocation.

`mac` reports when SSH does not answer within 5 minutes. A storage folder under 10 GB means macOS is not installed yet: the owner installs it in the web viewer at `https://mac.forge.shtrial.com`, or from a tunnel with `ssh -L 8006:127.0.0.1:8006 forge` and `http://localhost:8006`. Then enable Remote Login for user `maclab`.

## Guest state and setup (2026-11-12)

macOS 15.8.3 is installed, user `maclab`, no Apple Account. Its password is in `/root/.forge-mac-maclab-password` on forge (root only; never print or commit it), and `maclab` has passwordless sudo. The PC key `id_ed25519_macvm` is authorized, and `ssh forge-mac` works.

- **Host side is `../forge/host-setup.sh` with `../forge/compose.yml`.** The image is pinned (`dockurr/macos:3.12`), because `boot.sh` is copied from that exact image. Two known issues are fixed there:
  - [dockur/macos#572](https://github.com/dockur/macos/issues/572): `CPU_FLAGS: "+invtsc"`. Without it an Intel KVM guest can deadlock, with every vCPU at 100% and frozen block I/O. That is what hung the first install here; a restart only got past it by chance.
  - [dockur/macos#583](https://github.com/dockur/macos/issues/583): QEMU's `isa-applesmc` is dropped from `boot.sh`, so `PerfPowerServices` no longer pins a core. OpenCore's VirtualSMC supplies the OSK.
- **Resources:** 16 cores and 32 GB of the 32-core, 64 GB droplet; nothing else in the README bounds it on Intel. The "8 GB during installation" limit applies to AMD hosts only.
- **Spotlight indexing is off** (`sudo mdutil -a -i off`): `mds_stores` took most of a core after boot, and a build host needs no search index.
- **`mac` logs in as root on forge** with `/root/.ssh/forge-mac`, which is authorized in the guest. `mac status` reports "ssh: not ready" until that key is authorized.
- **macOS licence:** dockur's README says Apple's licence permits macOS only on Apple hardware. Running it here is the owner's decision, recorded 2026-11-11.
- **Remote Login** cannot be turned on with `systemsetup` (it needs Full Disk Access), so it was enabled with `sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.
- **Toolchain:** `../forge/guest-bootstrap.sh`. Homebrew refuses Intel Macs, so it installs Node 24, Ruby 3.4 (conda-forge, for fastlane and CocoaPods), ccache and xcodes from their own releases, and enables the corepack `pnpm` shim that EAS local builds spawn directly. It is idempotent.
- **Needs the owner:** an Apple ID session and an Expo session. An agent never holds either login. Measured 2026-11-12:
  - `xcodes install` with its own login returns HTTP 502 from Apple. Sign in with fastlane instead: `ssh -t forge-mac 'fastlane spaceauth -u <apple-id>'` (password and 2FA, answer `n` to the clipboard prompt). The session lands in `~/.fastlane/spaceship/<apple-id>/cookie`; xcodes reuses it with `--use-fastlane-auth --fastlane-user <apple-id>`.
  - xcodes 2.2.0 downloads the Apple silicon Xcode even on this x86_64 guest; its `xcodebuild` then fails with `Bad CPU type in executable`. Before installing, rewrite `Xcode_<v>_Apple_silicon.xip` to `Xcode_<v>_Universal.xip` in `~/Library/Application Support/com.robotsandpencils.xcodes/available-xcodes.json`, then `xcodes install <v> --use-fastlane-auth --fastlane-user <apple-id> --experimental-unxip --no-superuser --empty-trash` and run the `sudo` steps yourself (`xcode-select -s`, `xcodebuild -license accept`, `xcodebuild -runFirstLaunch`). xcodes asks for the `maclab` password even with passwordless sudo; with `--no-superuser` it does not.
  - Install the iOS simulator runtime (`xcodebuild -downloadPlatform iOS`, about 10 GB) even for device builds: actool needs it (`Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn`). XProtect scans the new runtime for about an hour at five cores; until it finishes, the first exec of an unsigned binary such as ccache blocks, so wait for `XprotectService` to go idle before the first build.
  - `ssh -t forge-mac 'eas login'` prints a browser link whose callback is `localhost` inside the guest. After signing in, paste the final callback URL back and `curl` it in the guest.
  - `~/Downloads` is TCC-protected over ssh; stage files elsewhere.
- **Console automation:** `mac-drive` on forge (OCR plus VNC) reads and clicks the guest screen. It was used for the Setup Assistant. Keep it for prompts that SSH cannot answer.
