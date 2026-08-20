---
name: use-chrome-devtools-mcp
description: Use when driving Chrome via chrome-devtools MCP tools (list_pages, take_snapshot, click, fill_form, network, console, performance), signing in to the dedicated automation profile, or resolving a browser provider. Prefer this skill over raw docs when selecting or sequencing DevTools MCP tools.
---

# Use Chrome DevTools MCP

<!-- skill-kind: provider-reference -->

Official tool catalog: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md  
Fleet setup: `docs/development/chrome-cdp.md` in agenthub · https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session

**Do not start here.** This file is the tool catalog for the one registered
browser server, not a routing skill, and everything below presumes a provider
has already been resolved to it. Enter through the skill that made that decision:

- `interactive-browser-testing` — visual product flows (`browser.isolated`)
- `browser-debugging` — console/network/performance/memory (`browser.isolated`)
- `browser-evidence` — screenshots/traces/Lighthouse artifacts (`browser.isolated`)

Each states its `## Capability required` and resolves a provider before sending
you here. If the running surface provides the capability natively — check
`hostSurfaces.surfaces` in `registry/fleet-profile.json` — drive that surface's
own browser and do not read on: starting `chrome-devtools` on a host
that already has a browser is the spawned-process-per-host cost that
`registry/mcps.json`'s `activationPolicy` exists to avoid.

That prior resolution is why this file is exempt from the routing contract in
`tests/Test-CapabilityRouting.ps1`, and why the exemption is declared as data at
the top rather than inferred. The exemption is not free: behavior 9 fails unless
a routing skill actually names this one and unless the server below is
registered. Deleting the `also load` line from all three routing skills makes
this file an orphan and turns it red.

---

## One server, one profile

There is a single MCP id: **`chrome-devtools`**. It serves both
`browser.authenticated` and `browser.isolated`, so no server choice is needed —
resolve the capability and go.

It passes **neither** `--isolated` nor `--autoConnect`, which means
chrome-devtools-mcp falls back to its default `userDataDir`,
`$HOME/.cache/chrome-devtools-mcp/chrome-profile`. That profile is:

- **separate from the owner's personal Chrome** — which is the isolation the
  QA and evidence skills actually require, and
- **persistent** — cookies survive a close, so a signed-in site is logged into
  once rather than on every session.

### Signing in (one time per site)

The profile starts empty. The first time a task needs a signed-in site, sign in
inside the automation browser; the session persists from then on. There is no
`chrome://inspect` step, no Allow dialog, and no dependency on Chrome 144+.

### What this deliberately gives up

Attaching to the page the owner is personally looking at right now. That was
`--autoConnect`, and it cost a manual `chrome://inspect/#remote-debugging`
enable plus an Allow click per connection, and it exposed **every open tab** of
the personal profile to the agent. If a task genuinely needs a live personal
session, use `--browserUrl` deliberately rather than reinstating a second
registration.

Two flags were retired on 2026-08-19: `--isolated` (wiped cookies on every
close, so every signed-in task re-authenticated) and `--autoConnect` (above).
They could never have been merged anyway — chrome-devtools-mcp declares
`conflicts: ['isolated', 'executablePath']` on `autoConnect`, so passing both
aborts startup. The retired id `chrome-devtools-isolated` resolves to
`chrome-devtools` through `migrationAliases`.

**Concurrency:** Chrome locks a user-data-dir, so this server is
single-shared-process by design. Do not run two sessions against it at once.

---

## Core agent loop (always)

```text
list_pages → select_page(pageId) → take_snapshot → act with uid → take_snapshot (or screenshot for visual proof)
```

Rules:

- Prefer **`take_snapshot`** over **`take_screenshot`** for choosing elements (uids from a11y tree).
- Always use the **latest** snapshot; uids go stale after navigation or large DOM changes.
- Prefer **`fill_form`** over many separate **`fill`** / **`click`** calls on forms.
- Prefer **`uid`**-based **`click`** / **`fill`** over coordinate **`click_at`** (needs `--experimentalVision`).

---

## Tool map (default categories)

Full parameters: official tool-reference.md. Below is routing, not a full schema dump.

### Navigation

| Tool | When |
|---|---|
| `list_pages` | Inventory tabs in the automation profile |
| `select_page` | Set context; optional `bringToFront` |
| `navigate_page` | url / back / forward / reload |
| `new_page` | Open URL in a new tab |
| `close_page` | Close by pageId (cannot close last page) |
| `wait_for` | Wait until any listed text appears |

### Input

| Tool | When |
|---|---|
| `click` | Click element `uid` (optional `dblClick`) |
| `fill` | One input/select/checkbox |
| `fill_form` | **Preferred** multi-field forms |
| `type_text` | Type into already-focused field |
| `press_key` | Enter, Tab, Control+A, etc. |
| `hover` / `drag` / `upload_file` / `handle_dialog` | As needed |
| `click_at` | Only with experimental vision flag |

### Debugging / evidence

| Tool | When |
|---|---|
| `list_console_messages` / `get_console_message` | JS errors, logs |
| `list_network_requests` / `get_network_request` | Failed loads, CORS, APIs; can use selected Network panel request |
| `evaluate_script` | Page JS; return JSON-serializable values only |
| `lighthouse_audit` | A11y/SEO/best-practices — **not** performance |
| `performance_start_trace` / `performance_stop_trace` / `performance_analyze_insight` | CWV / load speed |
| `take_screenshot` | Visual proof |
| `take_snapshot` | Action planning + selected Elements panel hint |

### Emulation

| Tool | When |
|---|---|
| `emulate` | dark/light, CPU, network throttle, UA, geolocation, viewport |
| `resize_page` | Window width/height |

### Off by default (need MCP flags — do not enable casually)

| Category | Flag | Tools |
|---|---|---|
| Deep memory | `--memoryDebugging` | heapsnapshot compare/retainers/… |
| Extensions | `--categoryExtensions` | install/list/reload/… (pipe only) |
| Screencast | `--experimentalScreencast` | start/stop video |
| Third-party page tools | `--categoryExperimentalThirdParty` | page-exposed tools |
| WebMCP | `--categoryExperimentalWebmcp` | WebMCP tools |

Fleet default: **do not** turn these on unless the task explicitly needs them and the host config is updated.

---

## Anti-patterns

- Assuming the automation profile is already signed in to a site. Check, and sign in once if not.
- TaskBar `--remote-debugging-port=9222` on the **Default** profile (ignored since Chrome 136).
- Clicking without a fresh snapshot.
- Using Lighthouse for "make it faster" (use performance trace tools).
- Dumping raw heapsnapshots into model context.
- Reinstating a second server registration to get a profile variant. Use `--browserUrl` for a one-off instead.

---

## Minimal smoke checks

1. `list_pages` after navigate → only pages this MCP session opened.  
2. No personal cookies or sites appear unless the task navigated there
   deliberately — the automation profile is separate from personal Chrome.  
3. `select_page` → `take_snapshot` → structure matches the page just opened.

**Signed-in check**, when the task needs an authenticated site: navigate to it
and confirm it is already logged in. If it is not, sign in once — the profile
persists, so later sessions skip this.
