# Physical iPhone from Windows

Read when driving the iPhone attached over USB: tap, type, swipe, read the screen, and before saying a phone task cannot be done: the route below taps and reads any app. Needs no Mac and no Appium. Admin is needed only to start the Apple Mobile Device Service, which is Manual and often stopped (`Start-Service 'Apple Mobile Device Service'` in an elevated shell); nothing else is elevated. Tool: `pymobiledevice3` (uv tool, `%USERPROFILE%/.local/bin/pymobiledevice3.exe`). On iOS 17+ developer commands open their own userspace tunnel; `remote tunneld` is not needed.

Exercised 2026-11-10 on iOS 27.2.1 from Windows, driving a third-party app end to end (rename, delete, reorder list entries), and again 2026-11-18 with `pymobiledevice3` 11.52.1: element clicks through a study app's review flow, a USB install confirmed by the phone, and a media file pushed into another app's Documents (sections below).

## Rules

- Hold `Global\AgentHub.MobileDeviceLab.ForegroundMutation` around every sequence that changes the foreground (launch, tap, type, buttons, mid-flow screenshots).
- The phone is kept unlocked (Auto-Lock Never while plugged in) and the owner says nobody else uses it (2026-11-18): start the runner and work. Do not ask beforehand whether it is unlocked or free. Never enter, guess or type the passcode. Ask the owner only when a command actually fails with `DeviceLocked` or the screen shows the lock screen or an app lock.
- **Someone else's lease is not yours to clear.** When the mutex is busy, wait (`scripts/Enter-MobileLabLease.ps1` reports the holder and its expiry) and never kill the holder, its XCTest runner or its port forward, even when the process that launched them is gone: on 2026-11-18 a Hold lease whose launcher had exited kept the mutex until its 120-minute timeout. Start only what you start and stop only that.
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
| Find | `POST /elements {"using":"xpath","value":"..."}`, or by predicate or class chain (next two rows) |
| Find by predicate | `{"using":"predicate string","value":"label == 'General' AND type == 'XCUIElementTypeCell'"}`. Faster than XPath on long lists, and the click goes to the element, so it survives a layout that shifts |
| Find by class chain | `{"using":"class chain","value":"**/XCUIElementTypeCell[`label == 'General'`]"}` |
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

`wda.one_predicate(...)` and `wda.one_class_chain(...)` send the two strategies above (the `using` strings are exactly `predicate string` and `class chain`, from WebDriverAgent's `FBFindElementCommands.m`; Appium clients prefix them with `-ios`). It refuses any address that is not the localhost forward. Its offline tests (`tests/test_wda_client.py`) run against a loopback stand-in; the class form has not been run against the phone, so read one screen with it before trusting a write. What did run on the phone (2026-11-18, raw HTTP, not this class): predicate-string `/elements` followed by `/element/<id>/click` advanced a study app's review screen to a chosen card where coordinate taps had missed, because a longer question wrapped to another line and moved the options. A live run of the helper on 2026-11-18 was blocked by another holder's lease and was not retried.

Prerequisites, all true on 2026-11-10 with `pymobiledevice3` 10.2.1 and again on 2026-11-12 with 11.52.1 (the runner still launched): use 11.52 or later on iOS 27.2.1, because 10.2.1 warns "Downloaded personalized image has unexpected ProductBuildVersion" and its screenshots time out. Stop every `pymobiledevice3` process before `uv tool upgrade pymobiledevice3`: a running tunnel locks a `.pyd` and leaves a half-upgraded tool (repair with `uv tool install --force pymobiledevice3`). Apple Mobile Device Service running, phone unlocked and trusted, Developer Mode on, developer disk image mounted. Nothing was elevated and no tunnel was started by hand. When the runner's signing expires is not established; check its provisioning profile in the macOS guest before relying on a date.

### What costs time

- Coordinates are only as good as the last screenshot. A longer string wraps, the rows below it move, and a tap lands on the wrong control. Locate by predicate and click the element, or read the rect again first.
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
| App Documents | `HouseArrestService` with `documents_only=True`, or `apps push/pull`; see "Push a file into an app's Documents" |
| Confirm an install | `apps query <bundle>`, then compare `CFBundleVersion`; see "Install and confirm" |
| Logs, crashes | `syslog live`, `crash pull <dir>` |
| Location | `developer dvt simulate-location set <lat> <lon>` |
| Appearance, clipboard | `developer core-device user-interface-style dark` or `light`; `copy`, `paste` |

## Install and confirm

```powershell
& $p afc rm /PublicStaging/pymobiledevice3 2>$null    # an interrupted upload leaves a partial file that hangs the next install
& $p apps install <ipa>                               # wrap in a 300 s timeout: a dropped USB link can otherwise hang for 40 minutes
& $p apps query <bundle>                              # JSON; read CFBundleVersion
```

`apps install` exits 0 even when `usbmuxd` is unreachable (seen 2026-11-11), so an install is claimed only when `apps query` reports the build you installed. Confirmed this way on 2026-11-18 for a build produced in the macOS guest. A confirmed install is not a device test: drive the app and say which target was exercised.

## Push a file into an app's Documents

Works for apps that expose their Documents folder, such as VLC (`org.videolan.vlc-ios`). Always read the file back and compare hashes.

```python
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
import hashlib, inspect

async def call(fn, *args):                      # some versions return coroutines, others plain values
    result = fn(*args)
    return await result if inspect.isawaitable(result) else result

lockdown = await call(create_using_usbmux)
svc = await call(HouseArrestService.create, lockdown, "org.videolan.vlc-ios", True)   # documents_only
names = await call(svc.listdir, "/Documents/<folder>")
await call(svc.set_file_contents, "/Documents/<folder>/<file>", data)
back = await call(svc.get_file_contents, "/Documents/<folder>/<file>")
assert hashlib.sha256(back).hexdigest() == hashlib.sha256(data).hexdigest()
```

Verified 2026-11-18: a 9 MB mp3 replaced in place and read back identical. Not checked: that VLC's own library showed the new file without a rescan.

## Scripting pymobiledevice3 from Python

The system Python cannot import it: use the Python of the uv tool (`uv tool dir`, then `pymobiledevice3\Scripts\python.exe`). Version 11.52.1 worked on iOS 27.2.1; PyPI had 11.59.0 on 2026-11-18, which was not tried here. Stop every `pymobiledevice3` process before upgrading (see Prerequisites).

## Flaky uploads from this PC

Long single uploads to sh-forge and to the macOS guest are reset past a few MB. Send 2-4 MB parts, retry and hash each part, reassemble on the far side and hash the whole before using it. Rexa's `scripts/droplet.mjs` and `scripts/ios/guest-sync.sh` do this.

## Pair the UI with API fixtures

Do not tap through screens to set up data. Create the synthetic account, record or appointment through a test API, launch the real app, drive only the workflow under test, then compare what the phone shows with what the backend saved and keep the screenshots and logs with the pull request or issue. Where the product handles health data, the synthetic-data rule in `SKILL.md` applies without exception.

## Other routes considered (primary sources read 2026-11-18, none installed here)

| Route | What its own docs say | Verdict for this PC and phone |
| --- | --- | --- |
| `iphone-cli` (`iph`, github.com/HyunSeob/iphone-cli) | MIT, Rust. Reads the accessibility tree and injects touch with no WebDriverAgent and nothing installed on the phone. Needs iOS 27 or later; v0.1.5, about five days old, about 100 stars; its README reports checks on iOS 27.0.1 and 27.2 over USB. On Windows it needs Apple's device support | The only route that avoids signing, and this phone is on iOS 27.2.1. Worth a trial, but it is a downloaded binary: get the owner's yes for the exact release first, run it beside the WDA route, and do not replace WDA until it has driven a real flow here |
| Tapwright (PyPI `tapwright`) | MIT. MCP server, learns and replays navigation. iOS 17 or later. Needs a signed WebDriverAgent from an App Store Connect API key or your own development certificate and profile. 1.8.0, six releases in four days, 5 stars on GitHub, tested on one iPhone 14 Pro Max | Duplicates what the existing signed runner already does. Skip unless MCP replay of recorded flows becomes the need |
| SideTap (github.com/ucsandman/SideTap) | MIT. Live viewer, UI tree, stop button, built on WebDriverAgent. Free Apple ID signing expires every 7 days | A viewer on top of the same mechanism. Not needed |
| iCTRL (github.com/OpenMinis/iCTRL) | Apache-2.0 from 1.32.0 (AGPL before). Paired JSON-RPC on port 8200 over an XCUITest runner on the phone, `/skill` endpoint | Another runner to sign and keep alive. Skip |
| pymobiledevice3 plugin | `/plugin marketplace add doronz88/pymobiledevice3`, then `/plugin install pymobiledevice3-device-operator@pymobiledevice3`. GPL-3.0-or-later project | Optional extra skill for the same CLI this reference already uses. Not installed; review its skill text before enabling |

None of these bypasses Face ID or an app's own lock, reaches another app's private data, or works without Developer Mode on the phone. Never expose WebDriverAgent or any of these services beyond `127.0.0.1`; a cloud agent cannot see a USB device and needs an authenticated gateway on the PC, which does not exist here.

## Last resort: the HID service

`developer core-device universal-hid-service tap|drag|type` (X = px/1179*65535, Y = px/2556*65535) and the browser viewer `developer core-device display serve-web --bind 127.0.0.1 --http-port 8771 --no-audio` share one path. On 2026-11-10 five drags worked, then every call raised `TimeoutError` in DisplayService and stayed dead through waits of 75 and 100 seconds, an app relaunch and the batched `session` mode. Use WebDriverAgent first.

## Rebuilding the runner

A signed runner exists in the macOS VM (SSH alias `macvm`) and as `%LOCALAPPDATA%/AgentHub/mobile-device-lab/wda/WebDriverAgentRunner-Runner.app.zip`. Its development identity and provisioning profiles for this phone live in the VM keychain `CodexWDA.keychain-db`; never print its password file. Rebuild with `~/Library/Application Support/CodexWDA/ios-wda.sh`, setting `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Start the VM only for a rebuild (`vmrun -T ws start <vmx> nogui`) and stop it afterwards. Install the rebuilt runner with `apps install`.
