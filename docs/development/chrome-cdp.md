# Browser automation (Playwright MCP) — fleet standard

**Updated:** 2026-10-23
**Official sources:**
- https://github.com/microsoft/playwright-mcp
- https://playwright.dev/docs/getting-started-cli
- https://playwright.dev/docs/intro

## Agent guidance (prefer skills over this doc)

| Asset | Role |
|---|---|
| **Routers** `interactive-browser-testing`, `browser-debugging`, `browser-evidence` | Capability + lane selection |
| **Catalog** `use-playwright-mcp` | Microsoft Playwright MCP `browser_*` tools (no fleet video) |
| **Catalog** `use-playwright-cli` | Playwright CLI for coding agents, including session video and traces |
| **Catalog** `use-playwright-test` | Playwright Test regressions |
| **Catalog** `desktop-evidence` | Windows desktop/window capture via `packages/browser-toolkit/scripts/Capture-Screen.ps1` |
| **This doc** | Owner / migration notes |
| **Upstream** Playwright MCP README | Full tool schemas (do not fork) |

Evidence files (browser and desktop) go to `%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\`. Never commit them.

Plugin package: `packages/browser-toolkit`. Codex, Cursor and Claude use their
native browser pane. Hosts without one use Playwright. Chrome DevTools MCP
is retired; do not install or register it.

## Goal

| Work type | Lane | What the agent drives |
|---|---|---|
| Coding-agent capture / repeatable steps / **session video / traces** | Playwright CLI (`@playwright/cli@0.1.17`) | Named headed sessions |
| Exploratory persistent reasoning (stills, console, network) | MCP id `playwright` (plugin, `--extension`) | Owner Chrome/Edge tabs |
| Committed regression | Playwright Test | Repo `@playwright/test` suite |
| Host already has a browser | Surface-native | Whatever `hostSurfaces` records |
| Native Windows window or whole desktop | `desktop-evidence` | `Capture-Screen.ps1` (FFmpeg `gdigrab`) |

## MCP config (plugin only, never host `mcpServers`)

Shipped in `packages/browser-toolkit/.mcp.json`. Enable `browser-toolkit` when
needed; disable when done. Do not write these into host MCP config.

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@0.0.79", "--extension"]
    }
  }
}
```

Headed by default — do not add `--headless`. Registry of record:
`registry/mcps.json`. Playwright Extension id
`mmlmfjhmonkocbjadbfplnigmagldckm`.

## Profile semantics

`--extension` reuses the owner's Chrome/Edge profile through the Playwright
extension. It is not persisted as a session-start launcher in host config.

## Migration

| Date | Change |
|---|---|
| 2026-08-19 | Isolated chrome-devtools launched profile replaced by Playwright MCP (workspace profile) so hosts could fan out |
| 2026-09-07 | Playwright withdrawn from persisted host config after session-start fan-out was measured live. Plugin-gated `playwright --extension` and `chrome-devtools --autoConnect` are the attach path. `chrome-devtools-isolated` aliases to `chrome-devtools`. Isolated Chromium launch is not the fleet MCP default |
| 2026-10-23 | Owner retired Chrome DevTools MCP everywhere, including its old alias. Native browser panes serve Codex, Cursor and Claude; other hosts keep Playwright only. This supersedes the historical attach route above. |

Sync removes retired Chrome DevTools IDs without requiring broad prune and
rejects the retired package even if it is registered under another name.

## CLI lane (coding agents)

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 install --skills
```

Microsoft recommends CLI + Skills for coding agents (token-efficient) and MCP for
specialized persistent exploratory loops. Fleet Playwright MCP args are
`--extension` only in the plugin MCP. Session video stays the CLI lane.
