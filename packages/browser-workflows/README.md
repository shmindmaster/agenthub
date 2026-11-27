# AH Browser Workflows

Run end-to-end browser workflows for personal productivity, portfolio operations, product testing, structured extraction and recorded demonstrations.

The four skills use Tencent BrowserSkill through the host shell. Install the upstream CLI and matching browser extension on the controlling host, connect the intended Chromium profile, and verify it with bsk doctor and bsk browsers --json. CLI access avoids starting a browser server for every agent conversation. Hosts that explicitly prefer MCP may run bsk mcp over stdio with BSK_RECIPES=1 for recipes. Remote agents need their own authorized browser connection or a paired controller.

## Background work

Connect a dedicated browser profile and set its BrowserSkill label to `Edge Automation`. A host can deliberately select another automation profile using `AGENTHUB_BROWSER_PROFILE` and `AGENTHUB_BROWSER_ENGINE`. Each job starts through the launcher bundled with `browser-operate`, which resolves one matching instance and sets `--no-focus`. An unavailable or ambiguous configured profile is a startup error.

Use a separate session ID and task-owned tabs for each parallel job. BrowserSkill 0.5.0 uses separate Agent Windows even inside one browser profile. Sessions share that profile's cookies and sign-in state. Tab groups are organizational and do not isolate accounts. BrowserSkill allows one active video recording per connected browser. For concurrent video captures, use separate connected browser instances or an isolated headless capture tool. Requests for human help, interactive action recording, tab borrowing and native popups have additional focus or ownership effects. Keep those out of ordinary unattended work.

[BrowserSkill manual](https://browserskill.weixin.qq.com/manual.en.html)

### Browser workflow acceptance

Use the repository's [synthetic browser round-trip test](../../tests/browser-roundtrip/README.md) when validating a host installation end to end. The suite exercises file intake, persisted readback, byte-for-byte download and silent recording.
