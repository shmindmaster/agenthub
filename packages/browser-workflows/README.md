# AH Browser Workflows

Run end-to-end browser workflows for personal productivity, portfolio operations, product testing, structured extraction and recorded demonstrations.

The four skills use Tencent BrowserSkill through the host shell. Install the upstream CLI and matching browser extension on the controlling host, connect the intended Chromium profile, and verify it with bsk doctor and bsk browsers --json. CLI access avoids starting a browser server for every agent conversation. Hosts that explicitly prefer MCP may run bsk mcp over stdio with BSK_RECIPES=1 for recipes. Remote agents need their own authorized browser connection or a paired controller.

[BrowserSkill manual](https://browserskill.weixin.qq.com/manual.en.html)

### Browser workflow acceptance

Use the repository's [synthetic browser round-trip test](../../tests/browser-roundtrip/README.md) when validating a host installation end to end. The suite exercises file intake, persisted readback, byte-for-byte download and silent recording.
