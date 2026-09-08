# Browser automation (Playwright MCP) — fleet standard

**Updated:** 2026-09-07  
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

Plugin package: `packages/browser-toolkit`.

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
    },
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@1.8.0", "--autoConnect", "--no-usage-statistics"]
    }
  }
}
```

Headed by default — do not add `--headless`. Registry of record:
`registry/mcps.json`. Playwright Extension id
`mmlmfjhmonkocbjadbfplnigmagldckm`. Chrome 144+ remote debugging at
`chrome://inspect/#remote-debugging`, then Allow.

## Profile semantics

`--extension` reuses the owner's Chrome/Edge profile. `--autoConnect` attaches
to the running Chrome after `chrome://inspect/#remote-debugging` and Allow.
Neither is persisted in host config. The launched chrome-devtools user-data-dir
under the user cache is not the fleet path.

## Migration

| Date | Change |
|---|---|
| 2026-08-19 | Isolated chrome-devtools launched profile replaced by Playwright MCP (workspace profile) so hosts could fan out |
| 2026-09-07 | Playwright withdrawn from persisted host config after session-start fan-out was measured live. Plugin-gated `playwright --extension` and `chrome-devtools --autoConnect` are the attach path. `chrome-devtools-isolated` aliases to `chrome-devtools`. Isolated Chromium launch is not the fleet MCP default |

Do not persist a launched chrome-devtools user-data-dir: one shared profile
directory still cannot fan out. `--autoConnect` attach does not use that path.

## CLI lane (coding agents)

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 install --skills
```

Microsoft recommends CLI + Skills for coding agents (token-efficient) and MCP for
specialized persistent exploratory loops. Fleet Playwright MCP args are
`--extension` only in the plugin MCP. Session video stays the CLI lane. Chrome
DevTools MCP is the sibling plugin server (`--autoConnect`), not a persisted
host config entry.
