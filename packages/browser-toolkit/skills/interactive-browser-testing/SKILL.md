---
name: interactive-browser-testing
description: Use when a coding agent should visually inspect and interact with a real browser workflow instead of relying only on automated Playwright tests or source inspection.
---

# Interactive browser testing

After resolving a provider lane, load the matching catalog:

- `use-playwright-cli` — repeatable capture / coding-agent work (preferred default for coding agents)
- `use-playwright-mcp` — exploratory persistent browser reasoning
- `use-playwright-test` — regression once a bug/behavior is worth preserving

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A browser the agent drives itself with a throwaway or per-workspace profile,
carrying no signed-in session. Suits localhost and public pages. This is the
capability that scales across hosts, because no two sessions contend for one
profile directory -- Playwright MCP partitions automatically as
mcp-{channel}-{workspace-hash}, and --isolated removes the on-disk profile
entirely."

## Resolve a provider before choosing the lane

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, drive its
   own first-party browser and start nothing. This is the ordinary case for a host
   that ships a browser.
   <!-- resolution-step: surface-provided -->
2. Use `playwright` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` for `browser.isolated` -- when the surface records `false` or
   `null`, or when the run needs an exploratory persistent MCP loop (snapshots,
   console/network correlation) that the surface cannot reach. Load `use-playwright-mcp`.
   <!-- resolution-step: local-fallback -->
3. Prefer Playwright CLI for token-efficient coding-agent capture, named sessions,
   screenshots, traces, video, or locator generation when a persistent MCP loop is
   not required. Load `use-playwright-cli`:
   <!-- resolution-step: additional-lane -->

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 -s=<task-slug> snapshot
npx -y @playwright/cli@0.1.17 -s=<task-slug> show --annotate
```

4. After interactive discovery finds a regression worth preserving, add or update
   a repository Playwright Test and load `use-playwright-test`. Existing automated
   tests do not replace interactive rendered verification.
   <!-- resolution-step: additional-lane -->

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. A surface with no browser at all
(the Codex CLI and Codex IDE extension are recorded that way, with the vendor sentence
as evidence) routes to a Playwright lane rather than to nothing.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the MCP fallback for this skill; do not start it when the surface
already provides `browser.isolated`, and do not start it when the CLI lane already
covers the task.

### Lane selection (after capability resolution)

| Need | Lane | Catalog |
|---|---|---|
| Repeatable capture / coding-agent work | Playwright CLI | `use-playwright-cli` |
| Exploratory / persistent browser reasoning | Playwright MCP | `use-playwright-mcp` |
| Regression / reproducible automated test | Playwright Test | `use-playwright-test` |

Microsoft's own guidance matches this table: CLI + Skills for coding agents
(token-efficient); MCP for specialized persistent exploratory loops.


## Agent-directed loop

1. Read repository instructions and use its real startup command and port.
2. Establish the expected workflow, role, synthetic data, and success signal.
3. Open an isolated headed session. Capture a structural snapshot and a screenshot
   before acting.
4. Inspect the screenshot visually and the snapshot semantically. Check composition,
   clipping, overlap, feedback, focus, accessible names, and unexpected states.
5. Perform one meaningful interaction at a time. Wait for the visible result, then
   inspect snapshot, screenshot, console, and relevant network requests again.
6. Exercise the golden path and one relevant failure, recovery, permission, or empty
   state. Never invent inaccessible states.
7. Record exact evidence and close the named Playwright session when finished.

`playwright` MCP launches into a per-workspace profile that is separate from
personal Chrome (`registry/mcps.json`). Cookies can survive a close for that
workspace hash, so a signed-in test site is authenticated once rather than every
run -- but nothing from the owner's personal session leaks in. A surface recorded
as providing `browser.isolated` carries no signed-in session by that capability's
own definition. The Playwright CLI lane is neither: it is not a surface provider
and this repository records nothing about how it handles profiles, so do not
assume it is isolated -- establish it (or pass `--persistent` deliberately).

Connecting to the owner's already-running personal Chrome is a separate thing: it means
passing a browser-url attachment at invocation. This skill does not do that, and the
default profile mode never touches personal Chrome.
