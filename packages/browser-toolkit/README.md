# Browser Toolkit

One browser-quality plugin with one on-demand MCP server and three focused skills.

## Architecture

- The skills state the capability they need (`browser.isolated`) and resolve a
  provider at use time: the active surface's own browser first, when
  `registry/fleet-profile.json` -> `hostSurfaces` records that capability true for
  the running surface.
- Chrome DevTools MCP 1.6.0 is the declared fallback provider for that capability
  (`registry/mcps.json` -> `providesCapabilities`). It is reached when the surface
  records `false` or `null`, and for DevTools-protocol depth no surface offers:
  Lighthouse, performance traces, screencasts, and heap analysis.
- Playwright CLI 0.1.17 is invoked from the interactive-testing skill for compact
  multi-step actions, headed sessions, traces, screenshots, and recordings.
- Playwright MCP is intentionally not included. It overlaps browser automation and
  would create another persistent tool schema and local worker.

The MCP server starts only when the installed plugin is used. Its default browser is
headed but isolated in a temporary profile that is deleted when Chrome closes. It does
not connect to the normal personal Chrome profile. Usage statistics, update checks, and
CrUX URL lookups are disabled.

## Resolution-step markers

Each numbered step of a skill's `## Resolve a provider ...` section declares its role
in the resolution order with an HTML comment on the step, so the order is machine-
checkable without anyone reading the prose. HTML comments render as nothing, so the
skills read to an agent exactly as they did before.

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
