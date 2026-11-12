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

`mac` reports when SSH does not answer within 5 minutes. A storage folder under 10 GB means macOS is not installed yet: the owner installs it in the web viewer at `https://mac.forge.shtrial.com`, or from a tunnel with `ssh -L 8006:127.0.0.1:8006 forge` and `http://localhost:8006`. Then enable Remote Login for user `maclab`.

## Guest state and setup (2026-11-12)

macOS 15.8.3 is installed, user `maclab`, no Apple Account. Its password is in `/root/.forge-mac-maclab-password` on forge (root only; never print or commit it), and `maclab` has passwordless sudo. The PC key `id_ed25519_macvm` is authorized, and `ssh forge-mac` works.

- **Cores must be a power of two.** With `CPU_CORES: "14"` the installer spun every core with no disk I/O for more than 15 minutes. With 16 it finished. Keep 8, 16 or 32.
- **Remote Login** cannot be turned on with `systemsetup` (it needs Full Disk Access), so it was enabled with `sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist`.
- **Toolchain:** `../forge/guest-bootstrap.sh`. Homebrew refuses Intel Macs, so it installs Node 24, Ruby 3.4 (conda-forge, for fastlane and CocoaPods), ccache and xcodes from their own releases. It is idempotent.
- **Needs the owner:** Xcode (`ssh -t forge-mac 'xcodes install 26.6'`, Apple ID and 2FA) and an Expo session (`ssh -t forge-mac 'eas login'`), so `eas build --local` can fetch the EAS-managed signing credentials. An agent never holds either login.
- **Console automation:** `mac-drive` on forge (OCR plus VNC) reads and clicks the guest screen. It was used for the Setup Assistant. Keep it for prompts that SSH cannot answer.
