# Browser Toolkit

One browser-quality plugin with a single on-demand Microsoft Playwright MCP
server, three routing skills, four provider catalogs (MCP, CLI, Test, desktop),
and a Windows capture helper.

## Architecture

```text
interactive-browser-testing  ──┐
browser-debugging            ──┼── routers (capability + lane selection)
browser-evidence             ──┘
        │
        └── desktop-evidence when the target is not a browser

use-playwright-cli   ← provider catalog (coding-agent capture, **video**, traces)
use-playwright-mcp   ← provider catalog (exploratory persistent MCP; no fleet video)
use-playwright-test  ← provider catalog (regression suites)
desktop-evidence     ← provider catalog (Windows desktop/window via Capture-Screen.ps1)
```

Evidence root for stills, traces, and recordings (browser and desktop):

```text
%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\
```

- Skills that need synthetic/localhost QA state the capability `browser.isolated`
  and resolve: surface-native browser first, then a Playwright lane.
- **Lane selection** (after capability resolution):
  - **Playwright CLI** — preferred for coding agents; **required for session video and traces**
  - **Playwright MCP** (`playwright`) — exploratory / persistent reasoning loops (screenshots, snapshots, console, network). Fleet args do not pass `--caps=devtools`.
  - **Playwright Test** — committed regressions after interactive discovery
  - **Desktop helper** — native Windows window or whole-desktop capture via `scripts/Capture-Screen.ps1`
- Work that needs a signed-in automation profile uses the same `playwright` MCP
  id (`browser.authenticated`); the profile is per-workspace, not personal Chrome.
- Resolution: surface-native browser first (`registry/fleet-profile.json` →
  `hostSurfaces`), then the matching Playwright lane.
- Playwright MCP is Microsoft `@playwright/mcp@0.0.79` (headed Chromium). It is
  **not** Chrome DevTools MCP; tool names are `browser_*`.

### Skills (load by intent)

| Skill | Kind | When |
| --- | --- | --- |
| **`interactive-browser-testing`** | router | Visual product workflows (`browser.isolated`) |
| **`browser-debugging`** | router | Console/network/trace debugging (`browser.isolated`) |
| **`browser-evidence`** | router | Screenshots, traces, artifacts (`browser.isolated`); bounces desktop targets to `desktop-evidence` |
| **`use-playwright-cli`** | provider | CLI command catalog + session video/traces |
| **`use-playwright-mcp`** | provider | MCP `browser_*` tool catalog + profile semantics |
| **`use-playwright-test`** | provider | Promoting captures into `@playwright/test` |
| **`desktop-evidence`** | provider | Windows desktop/window capture helper |

Upstream MCP tools: https://github.com/microsoft/playwright-mcp/blob/main/README.md  
CLI for coding agents: https://playwright.dev/docs/getting-started-cli  
Do not fork the full schema; keep routing in skills and link upstream.

### Playwright MCP (fleet)

| Item | Value |
| --- | --- |
| Package | `@playwright/mcp@0.0.79 --extension` plus `chrome-devtools-mcp@1.8.0 --autoConnect` |
| Browser | Owner Chrome/Edge via Playwright Extension / Chrome 144+ remote debugging |
| Registry | `registry/mcps.json` ids `playwright`, `chrome-devtools` (on-demand-local, not persisted) |
| Activation | `browser-toolkit` plugin `.mcp.json` only |
| Docs | `docs/development/chrome-cdp.md` |

**Do not** persist either server in host MCP config.  
**Do not** put `--remote-debugging-port=9222` on the Default profile TaskBar shortcut (ignored since Chrome 136).  
Playwright MCP tools stay `browser_*`. Chrome DevTools MCP tools stay on the `chrome-devtools` server.

## Resolution-step markers

Each numbered step of a skill's `## Resolve a provider ...` section declares its role
in the resolution order with an HTML comment on the step, so the order is machine-
checkable without anyone reading the prose. An HTML comment renders as nothing in a
Markdown viewer, but that is not what reads these files: skills are deployed byte for
byte and an agent sees the raw text, markers included. Keep them terse.

| Marker | Meaning | Count per skill |
| --- | --- | --- |
| `<!-- resolution-step: surface-provided -->` | resolves the running surface's own provider from `hostSurfaces` | exactly one |
| `<!-- resolution-step: local-fallback -->` | reaches the locally started Playwright MCP fallback | exactly one |
| `<!-- resolution-step: additional-lane -->` | CLI and/or Test lanes that are neither of those two | any number, including none |

`tests/Test-CapabilityRouting.ps1` behavior 8 requires every numbered step in that
section to carry exactly one known marker, requires every marker in the file to sit on
such a step, and requires the `surface-provided` step to come before the
`local-fallback` step. A step with no marker fails; the marker is not optional.

Provider catalogs declare `<!-- skill-kind: provider-reference -->` and a
`<!-- provider-channel: mcp|cli|test -->` marker so behavior 9 can tell MCP
catalogs (must name a registered server) from CLI/Test catalogs (no MCP id).

## Validation

```powershell
pwsh -NoProfile -File tests/Test-BrowserServer.ps1
pwsh -NoProfile -File tests/Test-CapabilityRouting.ps1
pwsh -NoProfile -File tests/Test-CaptureScreen.ps1
pwsh -NoProfile -File scripts/Validate-AgentHub.ps1
```
