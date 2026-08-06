---
name: use-chrome-devtools-mcp
description: >
  Use when driving Chrome via chrome-devtools MCP tools (list_pages, take_snapshot,
  click, fill_form, network, console, performance), choosing --autoConnect vs
  --isolated, attaching to the owner's signed-in Chrome session, or after
  chrome://inspect/#remote-debugging setup. Prefer this skill over raw docs when
  selecting or sequencing DevTools MCP tools.
---

# Use Chrome DevTools MCP

Official tool catalog: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md  
Fleet setup: `docs/CHROME_CDP.md` in agenthub · https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session

This skill is the **tooling and connection guide**. For QA workflows, also load:

- `interactive-browser-testing` — visual product flows (`browser.isolated`)
- `browser-debugging` — console/network/performance/memory (`browser.isolated`)
- `browser-evidence` — screenshots/traces/Lighthouse artifacts (`browser.isolated`)

---

## Choose the MCP server first

| Need | MCP id (`registry/mcps.json`) | How it connects |
|---|---|---|
| Signed-in sites (LinkedIn, Gmail, job portals, cookies) | **`chrome-devtools`** | **`--autoConnect`** to owner's already-running Chrome |
| Localhost / public QA, no personal cookies | **`chrome-devtools-isolated`** | **`--isolated`** temp profile |

### Authenticated path (`browser.authenticated`)

1. Owner starts **normal TaskBar Chrome** (no `--remote-debugging-port` on Default — ignored since Chrome 136).
2. Owner enables `chrome://inspect/#remote-debugging` and Allows when prompted.
3. Agent uses MCP id **`chrome-devtools`** (`--autoConnect`).
4. First tool call may show Chrome **Allow** dialog + "controlled by automated test software" banner.
5. `list_pages` must show **real owner tabs**, not only `about:blank`. If only blank, wrong server or session still on old `--isolated`.

### Isolated path (`browser.isolated`)

Use **`chrome-devtools-isolated`**. Never attach personal Chrome for evidence/QA isolation.

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
| `list_pages` | Inventory tabs; verify autoConnect vs isolated |
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
| Extensions | `--categoryExtensions` | install/list/reload/… (pipe only; not autoConnect until Chrome notes say otherwise) |
| Screencast | `--experimentalScreencast` | start/stop video |
| Third-party page tools | `--categoryExperimentalThirdParty` | page-exposed tools |
| WebMCP | `--categoryExperimentalWebmcp` | WebMCP tools |

Fleet default: **do not** turn these on unless the task explicitly needs them and the host config is updated.

---

## Anti-patterns

- Spawning a second Chrome or `--isolated` when the task needs the owner's logins.
- TaskBar `--remote-debugging-port=9222` on the **Default** profile (ignored since Chrome 136).
- Clicking without a fresh snapshot.
- Using Lighthouse for "make it faster" (use performance trace tools).
- Dumping raw heapsnapshots into model context.
- Enabling extension category over autoConnect without checking current Chrome support notes.

---

## Minimal smoke checks

**autoConnect:**

1. Owner: remote debugging enabled; Chrome running.  
2. `list_pages` → multiple real URLs/titles.  
3. `select_page` → `take_snapshot` → titles/structure match what the owner sees.

**isolated:**

1. `list_pages` after navigate → only MCP session pages.  
2. No personal cookies/sites unless the test navigated there deliberately.
