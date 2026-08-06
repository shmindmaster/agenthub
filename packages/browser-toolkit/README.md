# Browser Toolkit

One browser-quality plugin with **two** on-demand Chrome DevTools MCP servers and **four** focused skills.

## Architecture

- Skills that need synthetic/localhost QA state the capability `browser.isolated` and
  fall back to **`chrome-devtools-isolated`** (`--isolated` temp profile).
- Work that needs the owner's signed-in Chrome (LinkedIn, job portals, etc.) is
  capability **`browser.authenticated`**, provided by **`chrome-devtools`**, which
  **attaches only** to TaskBar personal Chrome via CDP (never launches a blank profile).
- Resolution: surface-native browser first (`registry/fleet-profile.json` ->
  `hostSurfaces`), then the matching MCP fallback for the capability.
- Playwright CLI 0.1.17 remains the compact multi-step action lane for interactive testing.
- Playwright MCP is intentionally not included.

### Skills (load by intent)

| Skill | When |
| --- | --- |
| **`use-chrome-devtools-mcp`** | Tool catalog, core loop, autoConnect vs isolated, smoke checks |
| **`interactive-browser-testing`** | Visual product workflows (`browser.isolated`) |
| **`browser-debugging`** | Console/network/performance/memory (`browser.isolated`) |
| **`browser-evidence`** | Screenshots, traces, Lighthouse artifacts (`browser.isolated`) |

Upstream parameter bible: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md  
Do not fork the full schema; keep routing in the skill and link upstream.

### Personal Chrome (authenticated) — official path

| Item | Value |
| --- | --- |
| TaskBar pin | Normal **Google Chrome** (no special debug flags required) |
| Owner enable | `chrome://inspect/#remote-debugging` → enable |
| MCP | `chrome-devtools` with **`--autoConnect`** (Chrome ≥144) |
| Permission | Chrome **Allow** dialog when agent connects |
| Registry | `registry/mcps.json` ids `chrome-devtools` + `chrome-devtools-isolated` |
| Docs | `docs/CHROME_CDP.md` |

**Do not** put `--remote-debugging-port=9222` on the Default profile TaskBar shortcut (ignored since Chrome 136).  
**Do not** use `--isolated` for signed-in work.  
Usage statistics and CrUX are disabled on both MCP servers (`--no-usage-statistics`, `--no-performance-crux`).

## Resolution-step markers

Each numbered step of a skill's `## Resolve a provider ...` section declares its role
in the resolution order with an HTML comment on the step, so the order is machine-
checkable without anyone reading the prose. An HTML comment renders as nothing in a
Markdown viewer, but that is not what reads these files: skills are deployed byte for
byte and an agent sees the raw text, markers included. Keep them terse.

| Marker | Meaning | Count per skill |
| --- | --- | --- |
| `<!-- resolution-step: surface-provided -->` | resolves the running surface's own provider from `hostSurfaces` | exactly one |
| `<!-- resolution-step: local-fallback -->` | reaches the locally started fallback server | exactly one |
| `<!-- resolution-step: additional-lane -->` | a further option that is neither of those two (the Playwright CLI lane) | any number, including none |

`tests/Test-CapabilityRouting.ps1` behavior 8 requires every numbered step in that
section to carry exactly one known marker, requires every marker in the file to sit on
such a step, and requires the `surface-provided` step to come before the
`local-fallback` step. A step with no marker fails; the marker is not optional. The
role used to be inferred from each step's wording, which both rejected a correct step
that forward-referenced the fallback and accepted a step citing the registry for an
unrelated reason. The marker is a declaration and is trusted as one: put it on the step
it actually describes.

## Validation

```powershell
python C:\Users\SaroshHussain\.codex\skills\.system\plugin-creator\scripts\validate_plugin.py .
npx -y chrome-devtools-mcp@1.6.0 --help
```
