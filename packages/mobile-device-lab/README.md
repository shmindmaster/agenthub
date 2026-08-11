# Mobile Device Lab

One Appium MCP control plane for both mobile platforms, on hardware that is
already here. **Android runs natively on Windows; iOS runs in the existing
VMware macOS guest and is driven remotely.** No physical device, no paid Mac,
no cloud device farm, no subscription.

## Architecture

```
WINDOWS 11                                   VMware guest (macOS Tahoe 26.6.1, x86_64)
  agent (any AgentHub host)                    Appium 3.6.0 on 0.0.0.0:4723
    -> appium-mcp 1.92.0 ---------------+        XCUITest 12.3.1
         |                              |          WebDriverAgent (installed)
         | embedded UiAutomator2        |            iOS 26.5 Simulator -- iPhone 17
         v                              |
       adb -> Android emulator          +-- TCP 4723 over VMnet8
              (WHPX, local)                 192.168.133.1 -> guest
```

Android is **local mode** (omit `remoteServerUrl`; the MCP embeds UiAutomator2).
iOS is **remote mode** (`remoteServerUrl` points at the guest). Both sessions
can be alive at once and the agent switches between them.

## Verified 2026-08-10

| Check | Result |
| --- | --- |
| `appium driver doctor xcuitest` | 0 required fixes |
| WebDriverAgent build | `** TEST BUILD SUCCEEDED **` (3.5 min) |
| Windows -> guest `/status` | `ready: true`, Appium 3.6.0 |
| Raw W3C iOS session from Windows | created in 7s; 39,695-char page source; screenshot |
| MCP Android session (local) | created in 7s; screenshot |
| MCP iOS session (remote) | created in 17s; screenshot |
| Both sessions concurrent | 2 sessions listed, Android + iOS |
| Android + macOS VM + Simulator together | all three running simultaneously |

The Android capture was Rexa itself mid-session, not a stock home screen.

## Use it

```powershell
# Gate first -- names the one broken layer instead of leaving you to guess.
pwsh -NoProfile -File packages/mobile-device-lab/skills/mobile-device-lab/scripts/Test-MobileLab.ps1
```

Then load the **`mobile-device-lab`** skill and drive `appium-mobile`.

## Guest setup (once, idempotent)

```bash
scp -r packages/mobile-device-lab/skills/mobile-device-lab/scripts/guest/ macvm:~/mobile-lab/
ssh macvm 'bash ~/mobile-lab/setup-appium-guest.sh'
ssh macvm 'bash ~/mobile-lab/start-appium-guest.sh'   # launchd agent, survives reboot
```

Do **not** stage files in `~/Downloads`, `~/Desktop`, or `~/Documents` on the
guest — macOS TCC blocks sshd from all three and the failure looks like an
empty directory rather than a permission error.

## Read before changing versions

[architecture-decisions.md](./skills/mobile-device-lab/references/architecture-decisions.md)
records what was adopted, what was rejected, and the measurement behind each.
Several plausible "upgrades" — Node 22, Xcode 16 / iOS 18, a host-only NIC,
alternating Android and iOS — are already recorded there as dead ends on this
hardware, with the evidence.

## Relationship to Maestro

Complementary, not competing. Appium MCP is how an agent *investigates*
interactively; Maestro is how a finding becomes a committed regression flow in
CI (the fleet standard, run from EAS Workflows). A bug found here should
usually leave a Maestro flow behind.

## Limits

Nothing here proves real-hardware behaviour. A simulator exercises no real GPU,
camera, sensor, thermal, or store-signing path. Report "verified on simulator",
never "verified on device".
