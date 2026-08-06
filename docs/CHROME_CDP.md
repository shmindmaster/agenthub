# Chrome DevTools MCP — authenticated + isolated (fleet standard)

**Updated:** 2026-08-05  
**Official sources:**
- https://developer.chrome.com/blog/chrome-devtools-mcp
- https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session
- https://github.com/ChromeDevTools/chrome-devtools-mcp
- https://developer.chrome.com/blog/remote-debugging-port (Chrome 136+: no debug port on default profile)

## Agent guidance (prefer skill over this doc)

| Asset | Role |
|---|---|
| **Skill** `use-chrome-devtools-mcp` | Tool routing, core loop, autoConnect vs isolated (agents load this) |
| **This doc** | Owner setup + host MCP config |
| **Upstream** [tool-reference.md](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md) | Full parameter schema (do not fork) |

Plugin package: `packages/browser-toolkit` (MCP + four skills).

## Goal

| Work type | MCP id | Flag | Chrome the agent sees |
|---|---|---|---|
| Signed-in sites (LinkedIn, Gmail, job portals) | `chrome-devtools` | **`--autoConnect`** | Your **normal** TaskBar Chrome session |
| Localhost / public QA only | `chrome-devtools-isolated` | **`--isolated`** | Temporary blank profile |

## Authenticated path (do this)

### One-time / per session in Chrome

1. Start Chrome from TaskBar **Google Chrome** (normal shortcut, **no** debug flags required).
2. Open `chrome://inspect/#remote-debugging`
3. Enable remote debugging; accept the UI.
4. When an agent first connects, click **Allow** on the Chrome permission dialog.
5. Expect banner: *Chrome is being controlled by automated test software*.

### MCP config (all hosts)

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": [
        "-y",
        "chrome-devtools-mcp@1.6.0",
        "--autoConnect",
        "--no-usage-statistics",
        "--no-performance-crux"
      ],
      "env": {
        "CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS": "true"
      }
    },
    "chrome-devtools-isolated": {
      "command": "npx",
      "args": [
        "-y",
        "chrome-devtools-mcp@1.6.0",
        "--isolated",
        "--no-usage-statistics",
        "--no-performance-crux"
      ],
      "env": {
        "CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS": "true"
      }
    }
  }
}
```

Source of truth: `registry/mcps.json` + `packages/browser-toolkit/.mcp.json`.

### Why not TaskBar `--remote-debugging-port=9222` on Default?

From Chrome 136+, `--remote-debugging-port` is **ignored** on the **default user data directory**. That profile is your real Sarosh/Gmail session. So TaskBar flags looked right but 9222 stayed dead. Official fix for real sessions is **`--autoConnect`**, not 9222 on Default.

## Isolated path (QA)

Use `chrome-devtools-isolated` only. No cookies. Browser-toolkit skills that require `browser.isolated` resolve here.

## Owner steps after config change

1. Fully quit agent apps (Grok/Claude/Cursor sessions) so MCP processes restart.
2. Chrome running with remote debugging enabled.
3. New agent session → first browser tool → **Allow**.
4. `list_pages` should show **your** open tabs, not only `about:blank`.

## Security

autoConnect exposes your full browsing session to the agent (cookies, open tabs). Intentional high-trust local use only.
