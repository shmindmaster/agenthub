---
name: interactive-browser-testing
description: Use when a coding agent should visually inspect and interact with a real browser workflow instead of relying only on automated Playwright tests or source inspection.
---

# Interactive browser testing

For tool routing and the core loop, also load **`use-playwright-mcp`**.

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
2. Use `playwright` -- the declared fallback, `providesCapabilities`
   in `registry/mcps.json` for `browser.isolated` -- when the surface records
   `false` or `null`, or when the run needs accessibility snapshots, console/network
   correlation, Lighthouse, performance, screencasts, or memory analysis that the
   surface cannot reach.
   <!-- resolution-step: local-fallback -->
3. Use pinned Playwright CLI for token-efficient action sequences, multiple named
   sessions, screenshots, traces, video, or locator generation:
   <!-- resolution-step: additional-lane -->

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 -s=<task-slug> show --annotate
```

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. A surface with no browser at all
(the Codex CLI and Codex IDE extension are recorded that way, with the vendor sentence
as evidence) routes to the fallback rather than to nothing.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the QA fallback for this skill; do not start it when
the surface already provides `browser.isolated`.

Add repository Playwright tests only after discovering a regression worth preserving.
Existing automated tests do not replace interactive rendered verification.

## Agent-directed loop

1. Read repository instructions and use its real startup command and port.
2. Establish the expected workflow, role, synthetic data, and success signal.
3. Open an isolated headed session. Capture a snapshot and screenshot before acting.
4. Inspect the screenshot visually and the snapshot semantically. Check composition,
   clipping, overlap, feedback, focus, accessible names, and unexpected states.
5. Perform one meaningful interaction at a time. Wait for the visible result, then
   inspect screenshot, snapshot, console, and relevant network requests again.
6. Exercise the golden path and one relevant failure, recovery, permission, or empty
   state. Never invent inaccessible states.
7. Record exact evidence and close the named Playwright session when finished.

`playwright` launches into a dedicated persistent profile that is separate from
personal Chrome (`registry/mcps.json`). Cookies survive a close, so a signed-in test
site is authenticated once rather than every run -- but nothing from the owner's
personal session leaks in. A surface recorded as providing `browser.isolated` carries
no signed-in session by that capability's own definition. The Playwright CLI lane is
neither: it is not a surface provider and this repository records nothing about how
it handles profiles, so do not assume it is isolated -- establish it.

Connecting to the owner's already-running personal Chrome is a separate thing: it means
passing `--browserUrl` at invocation. This skill does not do that, and the default
profile mode never touches personal Chrome.
