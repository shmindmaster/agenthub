---
name: use-playwright-mcp
description: Use when driving browsers via Microsoft Playwright MCP tools (browser_tabs, browser_snapshot, browser_click, browser_fill_form, browser_network_requests, browser_console_messages), signing in on a per-workspace Playwright profile, or sequencing Playwright MCP after a router resolved to it.
---

# Use Playwright MCP

<!-- skill-kind: provider-reference -->
<!-- provider-channel: mcp -->

Official tools: https://github.com/microsoft/playwright-mcp/blob/main/README.md  
CLI vs MCP guidance: https://playwright.dev/docs/getting-started-cli  
Fleet MCP registration: `registry/mcps.json` id `playwright`

**Do not start here.** This file is the tool catalog for the registered
Playwright MCP server (`playwright`), not a routing skill. Enter through the
skill that chose this lane:

- `interactive-browser-testing` — visual product flows (`browser.isolated`)
- `browser-debugging` — console/network/trace debugging (`browser.isolated`)
- `browser-evidence` — screenshots/traces/artifacts (`browser.isolated`)

Each states its `## Capability required` and resolves a provider before sending
you here. If the running surface provides the capability natively — check
`hostSurfaces.surfaces` in `registry/fleet-profile.json` — drive that surface's
own browser and do not read on: starting `playwright` on a host that already
has a browser is the spawned-process-per-host cost that
`registry/mcps.json`'s `activationPolicy` exists to avoid.

That prior resolution is why this file is exempt from the routing contract in
`tests/Test-CapabilityRouting.ps1`, and why the exemption is declared as data at
the top rather than inferred. Behavior 9 fails unless a routing skill actually
names this one and unless the server below is registered.

Sibling provider catalogs (other lanes): `use-playwright-cli`,
`use-playwright-test`. Native Windows windows and the whole desktop are
`desktop-evidence`, not this server.

---

## One server, per-workspace profile

There is a single MCP id: **`playwright`**. It serves both
`browser.authenticated` and `browser.isolated` for hosts that lack a native
browser. Fleet config:

```text
npx -y @playwright/mcp@0.0.79 --browser chromium
```

(headed by default — do not add `--headless`).

Microsoft Playwright MCP partitions its user-data directory as
`mcp-{channel}-{workspace-hash}` (see `registry/mcps.json`). That is why it can
run as one process per host session without Chrome's single-profile lock. It is
**not** the retired chrome-devtools path `$HOME/.cache/chrome-devtools-mcp/chrome-profile`.

- **separate from the owner's personal Chrome** — QA and evidence stay clean
- **persistent per workspace hash** — cookies can survive a close for that
  workspace profile, so a signed-in test site is logged into once rather than
  every session
- **not shared across unrelated workspaces** — different workspace hashes get
  different profiles

### Signing in (one time per site per workspace profile)

The profile starts empty. The first time a task needs a signed-in site, sign in
inside the automation browser; the session persists for that workspace profile.
There is no `chrome://inspect` step and no dependency on Chrome 144+
`--autoConnect`.

### What this deliberately gives up

Attaching to the page the owner is personally looking at right now. That was
chrome-devtools `--autoConnect`, retired fleet-wide on 2026-08-19. If a task
genuinely needs a live personal session, use Playwright MCP's extension /
`--browser-url` attachment deliberately rather than reinstating a second
registration. Prefer storage-state fixtures for reproducible authenticated runs.

**Concurrency:** Playwright MCP is safe as one process per host session because
profiles are workspace-partitioned. Do not assume a single shared Chrome lock.

---

## When to use this lane (vs CLI / Test)

Prefer **Playwright MCP** when the agent needs a **persistent exploratory loop**:
iterative snapshot → reason → act → snapshot, live console/network correlation,
or long-running autonomous browser work where continuous context outweighs
token cost.

Prefer **`use-playwright-cli`** for coding-agent work that should stay
token-efficient, and **always** for session video and traces (fleet MCP does
not pass `--caps=devtools`). Prefer **`use-playwright-test`** for committed
regression suites.

---

## Core agent loop (always)

```text
browser_navigate → browser_snapshot → act with refs → browser_snapshot
(or browser_take_screenshot for visual proof only)
```

Tab inventory when needed:

```text
browser_tabs (action=list) → browser_tabs (action=select) → browser_snapshot
```

Rules:

- Prefer **`browser_snapshot`** over **`browser_take_screenshot`** for choosing
  elements (refs from the accessibility tree).
- Always use the **latest** snapshot; refs go stale after navigation or large
  DOM changes.
- Prefer **`browser_fill_form`** over many separate **`browser_type`** /
  **`browser_click`** calls on forms.
- Prefer ref-based **`browser_click`** / **`browser_type`** over coordinate
  clicks (`browser_mouse_*` needs vision caps).

---

## Tool map (default + common)

Full parameters: upstream README Tools section. Below is routing, not a schema dump.
Names match `@playwright/mcp` (`browser_*`), not Chrome DevTools MCP.

### Navigation / tabs

| Tool | When |
|---|---|
| `browser_navigate` | Open a URL |
| `browser_navigate_back` | History back |
| `browser_tabs` | list / new / close / select tabs |
| `browser_wait_for` | Wait for text, textGone, or time |
| `browser_close` | Close the page |

### Input

| Tool | When |
|---|---|
| `browser_click` | Click element ref |
| `browser_type` | Type into editable |
| `browser_fill_form` | **Preferred** multi-field forms |
| `browser_press_key` | Enter, Tab, shortcuts |
| `browser_hover` / `browser_drag` | As needed |
| `browser_file_upload` | Uploads |
| `browser_handle_dialog` | Accept/dismiss dialogs |
| `browser_select_option` | `<select>` options |

### Debugging / evidence

| Tool | When |
|---|---|
| `browser_console_messages` | JS errors, logs |
| `browser_network_requests` | Failed loads, APIs (numbered list) |
| `browser_network_request` | Full detail for one request index |
| `browser_evaluate` | Page JS; return JSON-serializable values |
| `browser_take_screenshot` | Visual proof (not for action planning) |
| `browser_snapshot` | Action planning via a11y tree |

### Emulation / resize

| Tool | When |
|---|---|
| `browser_resize` | Viewport width/height |

### Opt-in via `--caps` (do not enable casually)

Fleet default args do **not** pass extra caps. Session video and traces are the
Playwright CLI lane (`use-playwright-cli`), not an MCP cap. Do not add
`--caps=devtools` to `registry/mcps.json` for ordinary evidence work.

Microsoft Playwright MCP does **not** expose Chrome DevTools MCP names such as `list_pages`, `take_snapshot`, `fill_form`, or `lighthouse_audit`. If a task needs Lighthouse or heap-snapshot workflows, use Playwright Trace / CLI / Test lanes or a dedicated audit tool — do not invent DevTools MCP calls against `playwright`.

---

## Anti-patterns

- Calling Chrome DevTools MCP tool names against `@playwright/mcp`.
- Assuming the workspace profile is already signed in. Check, then sign in once.
- TaskBar `--remote-debugging-port=9222` on the **Default** profile (ignored since Chrome 136).
- Clicking without a fresh `browser_snapshot`.
- Dumping raw traces or videos into model context; save files under
  `%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\` and summarize.
- Reinstating a second server registration for a profile variant.

---

## Minimal smoke checks

1. `browser_navigate` to a known URL → title/content match.
2. `browser_tabs` list → only pages this MCP session opened.
3. `browser_snapshot` → structure matches the page just opened.
4. No personal cookies or sites appear unless the task navigated there
   deliberately.

**Signed-in check**, when needed: navigate and confirm login. If not, sign in
once — the workspace profile persists for later sessions.
