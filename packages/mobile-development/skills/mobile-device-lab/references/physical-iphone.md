# Physical iPhone from Windows

Read when driving the iPhone attached over USB. Needs no Mac, WebDriverAgent, signing or admin rights. Tool: `pymobiledevice3` (uv tool, `%USERPROFILE%/.local/bin/pymobiledevice3.exe`). On iOS 17+ developer commands open their own userspace tunnel; `remote tunneld` is not needed.

## Rules

- Hold `Global\AgentHub.MobileDeviceLab.ForegroundMutation` around every sequence that changes the foreground (launch, tap, type, buttons, mid-flow screenshots).
- The phone must be unlocked (Auto-Lock is Never while plugged in). Never enter, guess or type the passcode; if locked, ask the owner.
- Bind the live viewer to `127.0.0.1` only; its touch, button and key endpoints are unauthenticated.
- Leave tunnels and viewers you did not start alone.

## After each phone reboot

```powershell
$p = "$env:USERPROFILE\.local\bin\pymobiledevice3.exe"
& $p mounter auto-mount     # fails with DeviceLocked until unlocked
& $p mounter list           # non-empty means mounted
```

## Commands

| Need | Command |
| --- | --- |
| Device present | `usbmux list` |
| Install / uninstall | `apps install <ipa>` / `apps uninstall <bundle>` |
| Launch | `developer dvt launch <bundle>` |
| Screenshot (1179x2556) | `developer dvt screenshot out.png` |
| Tap | `developer core-device universal-hid-service tap X Y` with X = px/1179*65535, Y = px/2556*65535 |
| Swipe | `developer core-device universal-hid-service drag X1 Y1 X2 Y2` |
| Type | `developer core-device universal-hid-service type "text"` |
| Buttons | `developer core-device hid button home`, `lock`, `volume-up`, `volume-down` |
| On-screen text (no coordinates) | `developer accessibility list-items` |
| Live view | `developer core-device display serve-web --bind 127.0.0.1 --http-port 8771 --no-audio` |
| App Documents | `HouseArrestService` with `documents_only=True`, or `apps push/pull` |
| Logs, crashes | `syslog live`, `crash pull <dir>` |
| Location | `developer dvt simulate-location set <lat> <lon>` |
| Appearance, clipboard | `developer core-device user-interface-style dark` or `light`; `copy`, `paste` |

To tap by name: screenshot, find the element's pixel center, convert, tap; confirm the text with `accessibility list-items`.

## WebDriverAgent (element tree, tap by label)

A signed runner exists in the macOS VM (SSH alias `macvm`) and as `%LOCALAPPDATA%/AgentHub/mobile-device-lab/wda/WebDriverAgentRunner-Runner.app.zip`. Its development identity and provisioning profiles for this phone live in the VM keychain `CodexWDA.keychain-db`; never print its password file. Rebuild with `~/Library/Application Support/CodexWDA/ios-wda.sh`, setting `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Start the VM only for a rebuild (`vmrun -T ws start <vmx> nogui`) and stop it afterwards.

Install the runner with `apps install`, start it as an XCTest, forward device port 8100, then point Appium (`webDriverAgentUrl`) at it. Unverified on iOS 27 from Windows.
