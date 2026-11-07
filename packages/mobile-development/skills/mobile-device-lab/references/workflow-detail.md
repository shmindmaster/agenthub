# Workflow detail


## 5. Build, reload and troubleshoot

Reload JavaScript with Metro instead of rebuilding; rebuild only for native changes. Read `references/inner-loop.md` for the app under test. If a guest looks down, check SSH before `vmrun`. Read `references/lab-operations.md` for repair steps.

## 4. Drive

- Android: `appium-mobile:select_device` (android), then `appium-mobile:appium_session_management` create with `remoteServerUrl` omitted (selects the embedded driver).
- iOS: create with `remoteServerUrl` from the `start ios -Json` output; the guest address changes. Capabilities and device name come from `$mobile catalog device.ios-simulator -Json`. Do not set `appium:usePrebuiltWDA` on a first session.
- Prefer `appium-mobile:appium_get_page_source` and accessibility ids over screenshots and XPath.
- Web app in mobile browsers: `$mobile web <productId> -Url <url>`; the dev server must listen on `0.0.0.0`.
