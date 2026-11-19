# Mobile MCP and MobileBuildMCP

Read when driving a **real** iPhone or Android device, or when an iOS build, test or log needs Xcode. For the iPhone on USB from Windows, `physical-iphone.md` is the route that has driven real apps; start there. Appium (`appium-mobile`) stays the route for the Windows Android emulator and the Simulator until Mobile MCP has proven those.

## Mobile MCP (`mobile-mcp`, registry/mcps.json)

`@mobilenext/mobile-mcp`, pinned, on demand for claude and codex. One tool set for iOS and Android, real devices, emulators and simulators: list devices, install, launch, terminate, tap, swipe, type, press buttons, open URLs, list on-screen elements, screenshots, screen recording, device logs and crash reports. Start with `mobile_list_available_devices`.

| Target | Where it runs | State on 2026-11-11 |
| --- | --- | --- |
| iPhone on USB | the owner PC (Apple Mobile Device Service must be running) | Device list and app launch verified. Reading or tapping the screen needs the on-device agent, below |
| Android device or emulator | the PC with `adb`, or the remote Linux worker (`references/remote-android.md`) | Not yet exercised |
| iOS Simulator | the macOS guest on sh-forge | Not yet exercised |

**On-device agent for a real iPhone (one time).** `mobilecli agent install --device <udid> --provisioning-profile <file>` re-signs the agent with `/usr/bin/security`, which exists only on macOS, so the Windows CLI cannot do it. Re-sign it in the forge guest with the owner's signing identity and a development profile that lists the phone, copy the signed agent back, and install it over USB from the PC. An AdHoc distribution profile (the Rexa study builds) does not allow a debuggable agent. Record the profile used; never commit it.

Rules:
- Never call `mobile_login_to_cloud_provider` or the remote-device tools. Devices are local or on sh-forge only.
- A real-device result is "verified on device <name>, iOS <version>"; a Simulator result stays "verified on simulator".
- Product scope (`registry/mobile-scope.json`) and synthetic-data rules in `SKILL.md` apply unchanged.

## MobileBuildMCP (macOS only, not registered yet)

`getsentry/MobileBuildMCP` (formerly XcodeBuildMCP) gives agents xcodebuild, Simulator, log capture, debugging and signing tools. It needs macOS 14.5 or later with Xcode, so it runs inside the forge guest through the lease-holding `mac` command:

```powershell
ssh forge mac run 'npx -y mobilebuildmcp@<pinned version> tools'   # list its tools
```

It is not in registry/mcps.json: Xcode is not yet installed in the guest and no run has been verified. Register it, pinned and on demand, only after a verified run. It sends runtime error telemetry to Sentry by default; disable that per its Privacy & Telemetry docs before use.
