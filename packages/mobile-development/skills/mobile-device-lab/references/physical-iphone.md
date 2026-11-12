# Physical iPhone from Windows

Read when driving the iPhone attached over USB: tap, type, swipe, read the screen, and before saying a phone task cannot be done: the route below taps and reads any app. Needs no Mac and no Appium. Admin is needed only to start the Apple Mobile Device Service, which is Manual and often stopped (`Start-Service 'Apple Mobile Device Service'` in an elevated shell); nothing else is elevated. Tool: `pymobiledevice3` (uv tool, `%USERPROFILE%/.local/bin/pymobiledevice3.exe`). On iOS 17+ developer commands open their own userspace tunnel; `remote tunneld` is not needed.

Exercised 2026-11-10 on iOS 27.2.1 from Windows, driving a third-party app end to end (rename, delete, reorder list entries).

## Rules

- Hold `Global\AgentHub.MobileDeviceLab.ForegroundMutation` around every sequence that changes the foreground (launch, tap, type, buttons, mid-flow screenshots).
- The phone must be unlocked (Auto-Lock is Never while plugged in). Never enter, guess or type the passcode; if locked, ask the owner.
- **An app lock is a hard stop.** If an app shows Face ID or its own passcode, do not try to pass it. Ask the owner, then keep the app in the foreground under one session so it does not lock again.
- **Verify before every write.** Confirm you are on the expected screen. Require exactly one element to match before clicking. After typing, read the field's `value` back and save only on an exact match.
- **Mask what you read.** Strip one-time codes and other secrets from any screen text you log. Delete screenshots when the task ends.
- **Deleting inside a credentials app** needs the owner's explicit, itemised confirmation; take the narrowest option offered ("this app only").
- Bind forwarded ports and the live viewer to `127.0.0.1` only; their endpoints are unauthenticated.
- Stop what you started (the XCTest runner, the port forward, a viewer) when done. Leave tunnels and viewers you did not start alone.

## After each phone reboot

```powershell
$p = "$env:USERPROFILE\.local\bin\pymobiledevice3.exe"
& $p mounter auto-mount     # fails with DeviceLocked until unlocked
& $p mounter list           # non-empty means mounted
```

## Drive an app: WebDriverAgent over a forwarded port

This is the route that works. The signed runner is already on the phone as `com.shmindmaster.wda.runner.xctrunner`.

```powershell
# 1. Start the runner. Long-running: keep it in the background with no window.
& $p developer dvt xcuitest com.shmindmaster.wda.runner.xctrunner
# 2. About 15 seconds later:
& $p developer wda status            # "ready": true
# 3. Forward the port, localhost only.
& $p usbmux forward 8100 8100
# 4. One session per task. Prints a session id; pass it to every later call.
& $p developer wda launch <bundle>
```

A CLI call without `-s <session>` creates a new session and can push the app to the background. Plain HTTP to `http://127.0.0.1:8100` is faster and does more than the `developer wda` CLI.

All paths are under `/session/<sid>`:

| Need | Call |
| --- | --- |
| Read the whole screen | `GET /source?format=description`: type, rect and label of every element, off-screen rows included, in about 2 seconds. Parse this instead of taking screenshots. |
| Find | `POST /elements {"using":"xpath","value":"..."}` |
| Click, inspect, clear | `POST /element/<id>/click`, `GET /element/<id>/rect`, `GET /element/<id>/attribute/label` (or `value`, `name`), `POST /element/<id>/clear` |
| Tap a point | `POST /wda/tap {"x","y"}` in points: screenshot pixels divided by 3 on this phone (393 points wide) |
| Type into the focused field | `POST /wda/keys {"value": ["c","h","a","r","s"]}` |
| Scroll, swipe to reveal | `POST /wda/dragfromtoforduration {"fromX","fromY","toX","toY","duration"}` |
| Picture, when a view exposes nothing to accessibility | `pymobiledevice3 developer wda screenshot -s <sid> out.png`, then tap by coordinate |

### Helper

`scripts/wda_client.py` wraps these calls with the rules built in (standard library only):

```python
from wda_client import Wda
wda = Wda(session_id, mask=r"\d{3} ?\d{3}(?!\d)")   # one-time codes never reach a log
rows = wda.screen()                                   # (type, x, y, w, h, label) for the whole screen
el = wda.one("//XCUIElementTypeCell[starts-with(@label,'Work email')]")   # None unless exactly one matches
if el and wda.type_checked(field, "New name"): ...    # save only when the text reads back exactly
wda.back()                                            # only if a real Back button exists
```

It refuses any address that is not the localhost forward. Its offline tests (`tests/test_wda_client.py`) run against a loopback stand-in; the class form has not been run against the phone, so read one screen with it before trusting a write.

Prerequisites, all true on 2026-11-10 with `pymobiledevice3` 10.2.1 and again on 2026-11-12 with 11.52.1 (the runner still launched): use 11.52 or later on iOS 27.2.1, because 10.2.1 warns "Downloaded personalized image has unexpected ProductBuildVersion" and its screenshots time out. Stop every `pymobiledevice3` process before `uv tool upgrade pymobiledevice3`: a running tunnel locks a `.pyd` and leaves a half-upgraded tool (repair with `uv tool install --force pymobiledevice3`). Apple Mobile Device Service running, phone unlocked and trusted, Developer Mode on, developer disk image mounted. Nothing was elevated and no tunnel was started by hand. When the runner's signing expires is not established; check its provisioning profile in the macOS guest before relying on a date.

### What costs time

- `contains(@label, ...)` can match several cells. Use `starts-with` on the full row label when rows are near-duplicates.
- A navigation bar's first button is not always Back: on a root screen it is the menu. Match `@label='Back'`.
- `POST /wda/element/<id>/scroll {"toVisible":true}` on a row near the top triggers pull-to-refresh. Scroll with short drags and read the rect again.
- Tap a row on its left side: a floating button can sit over the right edge of the last visible row.
- An accessibility-only button with a zero or off-screen rect takes about 19 seconds per click through `/element/<id>/click` and may apply late. If the control has a visible rect, tap its coordinates (about 1 second).

## Other commands

| Need | Command |
| --- | --- |
| Device present | `usbmux list` |
| Install / uninstall | `apps install <ipa>` / `apps uninstall <bundle>` |
| Launch without a session | `developer dvt launch <bundle>` |
| Screenshot (1179x2556) | `developer dvt screenshot out.png`; fails now and then when called back to back, so retry once |
| Buttons | `developer core-device hid button home`, `lock`, `volume-up`, `volume-down` |
| On-screen text | `developer accessibility list-items`; returns only part of a long list per call |
| App Documents | `HouseArrestService` with `documents_only=True`, or `apps push/pull` |
| Logs, crashes | `syslog live`, `crash pull <dir>` |
| Location | `developer dvt simulate-location set <lat> <lon>` |
| Appearance, clipboard | `developer core-device user-interface-style dark` or `light`; `copy`, `paste` |

## Last resort: the HID service

`developer core-device universal-hid-service tap|drag|type` (X = px/1179*65535, Y = px/2556*65535) and the browser viewer `developer core-device display serve-web --bind 127.0.0.1 --http-port 8771 --no-audio` share one path. On 2026-11-10 five drags worked, then every call raised `TimeoutError` in DisplayService and stayed dead through waits of 75 and 100 seconds, an app relaunch and the batched `session` mode. Use WebDriverAgent first.

## Rebuilding the runner

A signed runner exists in the macOS VM (SSH alias `macvm`) and as `%LOCALAPPDATA%/AgentHub/mobile-device-lab/wda/WebDriverAgentRunner-Runner.app.zip`. Its development identity and provisioning profiles for this phone live in the VM keychain `CodexWDA.keychain-db`; never print its password file. Rebuild with `~/Library/Application Support/CodexWDA/ios-wda.sh`, setting `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Start the VM only for a rebuild (`vmrun -T ws start <vmx> nogui`) and stop it afterwards. Install the rebuilt runner with `apps install`.
