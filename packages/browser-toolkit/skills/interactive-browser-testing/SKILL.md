---
name: interactive-browser-testing
description: Use when a coding agent should visually inspect and interact with a real browser workflow instead of relying only on automated Playwright tests or source inspection.
---

# Interactive browser testing

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A first-party browser the agent drives
itself, with its own profile. Suits localhost and public pages; carries no signed-in
session."

## Resolve a provider before choosing the lane

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, drive its
   own first-party browser and start nothing. This is the ordinary case for a host
   that ships a browser.
   <!-- resolution-step: surface-provided -->
2. Use `chrome-devtools` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` -- when the surface records `false` or `null`, or when the run
   needs accessibility snapshots, console/network correlation, Lighthouse,
   performance, screencasts, or memory analysis that the surface cannot reach.
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
`chrome-devtools` is the most widely declared local process in the fleet
(`localProcessPolicy.declaredByHostCount`), and every host that spawns its own `npx`
instance costs a separate browser-driving process, so a session that resolves
natively must not start one it never uses.

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

`chrome-devtools` is launched with `--isolated` into a temporary profile
(`registry/mcps.json`), and a surface recorded as providing `browser.isolated`
carries no signed-in session by that capability's own definition. The Playwright CLI
lane is neither: it is not a surface provider and this repository records nothing
about how it handles profiles, so do not assume it is isolated -- establish it.

Connecting to an already-running personal Chrome profile is `browser.authenticated`,
a different capability this skill does not request and must not obtain by other
means. It requires explicit authorization and Chrome remote debugging. Never attach
to ordinary personal browsing.
