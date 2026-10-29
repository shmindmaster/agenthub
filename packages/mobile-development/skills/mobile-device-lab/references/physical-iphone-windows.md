# Driving the attached physical iPhone from Windows

Verified 2026-10-28 on the owner's iPhone17,3 ("Shash", UDID `00008140-001924663A93801C`), iOS 27.0.1, USB,
Developer Mode on, with `pymobiledevice3` 10.2.1 installed as a uv tool
(`C:\Users\SaroshHussain\.local\bin\pymobiledevice3.exe`; this install includes pyimg4 and lzfse).

No Mac, no WebDriverAgent, no signing and no admin rights are needed for anything below. Developer commands
open a no-root userspace tunnel by themselves on iOS 17+; you don't need `remote tunneld`.

## Rules

- Hold the named mutex `Global\AgentHub.MobileDeviceLab.ForegroundMutation` around every sequence that
  changes the foreground (launch, tap, type, buttons, screenshots taken mid-flow).
- The phone must be unlocked. The owner set Auto-Lock to Never on 2026-10-28, so it stays unlocked while plugged in. Never enter, guess or type the passcode; if it's locked, ask the owner.
- Bind the live viewer to `127.0.0.1` only. Its touch, button and key endpoints have no authentication.
- Leave tunnels and viewers you didn't start alone.

## One-time setup (per phone reboot)

```powershell
$p = "$env:USERPROFILE\.local\bin\pymobiledevice3.exe"
& $p mounter auto-mount          # personalized developer disk image; fails with DeviceLocked until unlocked
& $p mounter list                # non-empty = mounted
```

## Commands

| Need | Command |
|---|---|
| Device present | `usbmux list` |
| Install / uninstall app | `apps install <ipa>` / `apps uninstall <bundle>` |
| Launch app | `developer dvt launch <bundle>` (kills an existing instance by default) |
| Screenshot (1179x2556) | `developer dvt screenshot out.png` |
| Tap | `developer core-device universal-hid-service tap X Y`. X and Y are normalized 0..65535: `X = px/1179*65535`, `Y = px/2556*65535` |
| Drag / swipe | `developer core-device universal-hid-service drag X1 Y1 X2 Y2` |
| Type text | `developer core-device universal-hid-service type "text"` |
| Hardware buttons | `developer core-device hid button home|lock|volume-up|volume-down` |
| Read on-screen text (flat list, no coordinates) | `developer accessibility list-items` |
| Live view, clickable, in a browser | `developer core-device display serve-web --bind 127.0.0.1 --http-port 8771 --no-audio`, then open `http://127.0.0.1:8771/` |
| Files in an app's Documents (e.g. VLC) | `HouseArrestService` with `documents_only=True` (Python API), or `apps push/pull` |
| Logs / crashes | `syslog live`, `crash pull <dir>` |
| Processes / performance | `developer dvt sysmon process ...`, `developer core-device list-processes` |
| Location | `developer dvt simulate-location set <lat> <lon>` |
| Dark mode, clipboard, rotate | `developer core-device user-interface-style dark|light`, `copy` / `paste`, `rotate` |
| Display state | `developer core-device get-display-info` (`backlightState`; `get-lockstate` is not implemented on iOS 27) |

To tap an element by name, take a screenshot, find the element's pixel center, and convert it to normalized
coordinates. Use `accessibility list-items` to confirm the text is on screen.

## WebDriverAgent (element tree, tap by label)

The signing material already exists in the macOS VM (`D:\VMs\macOS-Tahoe-AMD`, SSH alias `macvm`, user `maclab`),
created by a Codex session on 2026-08-18. Checked 2026-10-28:

- Identity `Apple Development: Sarosh Hussain (S62D6V5D8W)`, team `9V6CGU625U`, valid to 2027-08-18, in
  `~/Library/Keychains/CodexWDA.keychain-db` (password file next to the script below; never print it).
- Development profiles containing this iPhone's UDID, valid to 2027-08: `Codex WDA iPhone Development`
  (`com.shmindmaster.wda.runner`) and `Codex WDA Runner Development` (`...wda.runner.xctrunner`, uuid `6b3cb3df`).
- A signed runner built with Xcode 26.6 (iOS 26.4 SDK, minimum iOS 13), bundle
  `com.shmindmaster.wda.runner.xctrunner`. Rebuild and status script: `~/Library/Application Support/CodexWDA/ios-wda.sh`.
  Xcode lives on the `DeveloperData` volume; `xcode-select` points at Command Line Tools, so set
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for `xcodebuild`.
- Copy on Windows: `%LOCALAPPDATA%\AgentHub\mobile-device-lab\wda\WebDriverAgentRunner-Runner.app.zip`
  (SHA-256 `ED378D1F...4A6F4106`).

The phone stays on Windows. Install the runner with `apps install`, start it as an XCTest with pymobiledevice3
(or go-ios `runwda`), forward device port 8100, and point Appium (`webDriverAgentUrl`) or mobile-mcp at it.
Not yet verified on iOS 27 from Windows. Frida and debugserver/LLDB can use the same development identity.
Start the VM only when a rebuild is needed (`vmrun -T ws start <vmx> nogui`, then `ssh macvm`), and stop it after.
