---
name: use-playwright-cli
description: Use when a coding agent should drive browsers through Playwright CLI commands and installable Playwright CLI skills for token-efficient, repeatable capture — not through Playwright MCP tool schemas.
---

# Use Playwright CLI

<!-- skill-kind: provider-reference -->
<!-- provider-channel: cli -->

Official guide: https://playwright.dev/docs/getting-started-cli  
Upstream CLI: https://github.com/microsoft/playwright-cli

**Do not start here.** This file is the provider catalog for the Playwright CLI
lane after a routing skill chose it. Enter through:

- `interactive-browser-testing`
- `browser-debugging`
- `browser-evidence`

Sibling catalogs: `use-playwright-mcp` (exploratory MCP), `use-playwright-test`
(regression). Native Windows windows and the whole desktop are `desktop-evidence`,
not this lane.

This lane is **not** an MCP server. It does not appear in `registry/mcps.json`.
Fleet pin used by routing skills:

```powershell
npx -y @playwright/cli@0.1.17
```

---

## When to use this lane

Prefer **Playwright CLI + skills** when:

- the agent is primarily a **coding agent** balancing browser work with a large
  codebase and limited context
- the work is **repeatable capture** (screenshots, traces, videos, annotated
  steps) rather than a long exploratory reasoning loop
- token efficiency matters more than keeping a full MCP tool schema + verbose
  accessibility trees in context

Prefer **`use-playwright-mcp`** for persistent exploratory / autonomous loops.
Prefer **`use-playwright-test`** once a regression belongs in the repo test suite.

Microsoft documents this split explicitly: CLI + Skills for coding agents; MCP
for specialized agentic loops that need continuous browser context.

---

## Install / skills

```powershell
# one-shot via npx (fleet pin)
npx -y @playwright/cli@0.1.17 --help

# optional: install Playwright's official coding-agent skills into the host
npx -y @playwright/cli@0.1.17 install --skills
```

`install --skills` pulls upstream Playwright CLI skills for the current coding
agent. AgentHub does **not** vendor those skills; treat them as optional host
enhancements on top of this catalog.

---

## Named sessions (headed)

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 -s=<task-slug> snapshot
npx -y @playwright/cli@0.1.17 -s=<task-slug> screenshot
npx -y @playwright/cli@0.1.17 -s=<task-slug> show --annotate
```

Use a stable `-s=` session name per task so later commands attach to the same
browser. Close or delete session data when the task finishes.

Default CLI profile behavior is in-memory unless `--persistent` is passed; do
not assume isolation or persistence semantics match Playwright MCP's
workspace-hash profile. Establish what the session is doing for the task.

---

## Core commands (routing cheat sheet)

| Intent | Command sketch |
|---|---|
| Open | `open <url> --headed` |
| Navigate | `goto <url>` |
| Snapshot / refs | `snapshot` |
| Click / type / fill | `click <ref>`, `type …`, `fill <ref> …` |
| Screenshot | `screenshot` |
| Tabs | `tab-list`, `tab-new`, `tab-select` |
| Console / network | `console`, `requests` |
| Trace / video | **this lane** — `tracing-start` / `tracing-stop`, `video-start` / `video-stop`. Fleet Playwright MCP does not expose these. |
| Monitor | `show` |

Full command list: `npx -y @playwright/cli@0.1.17 --help` and upstream docs.
Do not paste MCP `browser_*` tool names into the CLI.

---

## Anti-patterns

- Loading Playwright MCP tool schemas into context for a CLI session.
- Assuming CLI sessions share the MCP workspace-hash profile.
- Leaving headed sessions open after the task.
- Checking raw video/trace blobs into a repository. Write them under the evidence
  root owned by `desktop-evidence`'s helper: `%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\`.
