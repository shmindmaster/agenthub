# macOS VM on sh-forge

Until 2026-12-01 iOS builds, Simulator runs and Xcode work run in the macOS VM on sh-forge: container `macos`, compose file `/opt/macos/compose.yml`. When it runs, it holds 24 GB of RAM and 14 cores of the shared droplet, so it starts only when work needs it and stops by itself afterwards. The local VMware VM is retired (`Invoke-MobileLabVmrunStart` refuses).

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
