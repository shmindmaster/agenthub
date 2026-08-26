# Browser automation (Playwright MCP) — fleet standard

**Updated:** 2026-08-21  
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
| Exploratory persistent reasoning (stills, console, network) | MCP id `playwright` | Per-workspace Chromium profile |
| Committed regression | Playwright Test | Repo `@playwright/test` suite |
| Host already has a browser | Surface-native | Whatever `hostSurfaces` records |
| Native Windows window or whole desktop | `desktop-evidence` | `Capture-Screen.ps1` (FFmpeg `gdigrab`) |

## MCP config (hosts without a native browser)

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@0.0.79", "--browser", "chromium"]
    }
  }
}
```

Headed by default — do not add `--headless`. Registry of record:
`registry/mcps.json`.

## Profile semantics

Playwright MCP partitions user data as `mcp-{channel}-{workspace-hash}`. That is
why the fleet can run one process per host session without Chrome's single
user-data-dir lock. It is **not** personal Chrome, and it is **not** the
retired chrome-devtools path under `$HOME/.cache/chrome-devtools-mcp/`.

## Migration (retired 2026-08-19)

| Retired | Current |
|---|---|
| `chrome-devtools` / `chrome-devtools-isolated` | `playwright` (see `migrationAliases`) |
| Chrome DevTools MCP tools (`list_pages`, `take_snapshot`, `fill_form`, …) | Playwright MCP tools (`browser_tabs`, `browser_snapshot`, `browser_fill_form`, …) |
| `--autoConnect` personal Chrome attachment as a second server | Deliberate `--browser-url` / extension attach only when required |

Do not reinstate Chrome DevTools MCP as a live fleet browser server: one shared
`$HOME` profile cannot fan out across hosts.

## CLI lane (coding agents)

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 install --skills
```

Microsoft recommends CLI + Skills for coding agents (token-efficient) and MCP for
specialized persistent exploratory loops. Fleet Playwright MCP args are
`--browser chromium` only: do not add `--caps=devtools` for video. Use the CLI
lane. Do not reinstate Chrome DevTools MCP as a live fleet browser server.
