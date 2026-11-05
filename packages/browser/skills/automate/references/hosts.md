# Which host has a browser

Use the host's own tool when the row says native. Otherwise use `scripts/browse.mjs`. Hosts change; trust a failed call over this table.

| Host | Native browser | Use |
|---|---|---|
| Claude Code | Claude in Chrome (your real Chrome, signed in) and the desktop browser pane | Native |
| Codex app | `@Browser`, `@Chrome`, Computer Use | Native; the Codex CLI is unreliable, use the client |
| Cursor IDE | `@browser` | Native; Cursor Agent CLI has none, use the client |
| VS Code (Copilot chat) | Integrated browser tools | Native |
| Qoder IDE | Browser Agent | Native; `qodercli` uses its `agent-browser` catalog plugin |
| Antigravity | Browser Subagent | Native |
| Factory Droid | droid-control, which runs agent-browser | Native |
| Gemini CLI | `browser_agent`, off by default | Use the client |
| Grok CLI | none | Use the client |
| Copilot CLI | screen-level computer use only | Use the client |
| Amp | none | Use the client |
| Cline CLI | official `agent-browser` plugin | Native |
| Devin CLI | none confirmed | Use the client |
| OpenCode CLI | none | Use the client |
| Warp | cloud sandbox only | Use the client |

Computer Use and any headed browser take the foreground and show a window. Avoid them for background work.

## Engines

- **agent-browser** is the default. `node scripts/browse.mjs doctor` reports whether it and Chrome are present. Install once with `npm i -g agent-browser && agent-browser install` (roughly 120 MB plus a Chrome download).
- **playwright-cli** is the second engine for a host that cannot run agent-browser, and for Firefox or WebKit. Run `playwright-cli --help`. Its security boundary is weaker; keep it on trusted sites.
- A host with no shell can use the Playwright MCP server, started with `--headless --isolated`. It costs more context per task than the CLIs.

## Signed-in sites

Prefer a native browser that already holds the user's session. With the client, use the `auth` vault, or `--profile <name>` on request. Attaching to a running Chrome (`--auto-connect`) shows a window and needs remote debugging switched on; do it only when the user asks.
