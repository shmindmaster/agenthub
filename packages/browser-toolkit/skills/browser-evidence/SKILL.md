---
name: browser-evidence
description: Use when an authorized workflow needs reproducible screenshots, accessibility snapshots, console or network records, traces, or screencasts.
---

# Browser evidence

This skill captures observed browser evidence. Product decisions remain with Product
Experience Engineering; video production and release decisions remain with
`media-studio` (live-product screencasts invoke the internal screencast engine).

After resolving a provider lane, load the matching catalog:

- `use-playwright-mcp` — snapshot/screenshot/console/network evidence in an exploratory loop
- `use-playwright-cli` — named-session screenshots, traces, and video for coding-agent capture
- `use-playwright-test` — fixture-backed evidence inside a regression suite when appropriate

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A browser the agent drives itself with a throwaway or per-workspace profile,
carrying no signed-in session. Suits localhost and public pages. This is the
capability that scales across hosts, because no two sessions contend for one
profile directory -- Playwright MCP partitions automatically as
mcp-{channel}-{workspace-hash}, and --isolated removes the on-disk profile
entirely."

Isolation is the point here, not an implementation detail: evidence must not carry
personal Chrome state, unrelated tabs, credentials, or customer data.

## Resolve a provider before capturing

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, capture
   with its own first-party browser and start nothing.
   <!-- resolution-step: surface-provided -->
2. Use `playwright` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` for `browser.isolated` -- when the surface records `false` or
   `null`, or when the evidence needed is MCP-side console/network/snapshot capture.
   Load `use-playwright-mcp`.
   <!-- resolution-step: local-fallback -->
3. Use Playwright CLI when named-session screenshots, traces, or video are the
   evidence form and a coding-agent CLI loop is enough. Load `use-playwright-cli`.
   <!-- resolution-step: additional-lane -->
4. Use Playwright Test when evidence belongs inside a committed regression run.
   Load `use-playwright-test`.
   <!-- resolution-step: additional-lane -->

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. Record which provider produced
each artifact, because a screenshot's meaning depends on the profile it came from.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the MCP QA fallback for this skill; do not start it when the surface
already provides `browser.isolated`. Its dedicated profile is separate from personal
Chrome, so evidence captures are isolated by construction. Attaching to the owner's
live personal Chrome would require a browser-url attachment deliberately and must not
be done for evidence captures.

Microsoft Playwright MCP does not expose Chrome DevTools MCP Lighthouse tools. Prefer
Playwright screenshots, snapshots, traces, and video for evidence; use a dedicated
audit tool only when Lighthouse-style scores are explicitly required.

## Procedure

1. Record build SHA, environment, role, URL, synthetic dataset, locale, timezone,
   viewport, zoom, color scheme, and reduced-motion setting.
2. Use the resolved provider's own isolated, headed profile, whatever browser it
   drives. Do not expose personal browser state, unrelated tabs, credentials, or
   customer data.
3. Capture a structural snapshot and screenshot before interaction. Use the snapshot
   for element identity and the screenshot for visual-model inspection of hierarchy,
   clipping, overlap, density, focus, feedback, and responsive behavior.
4. Exercise the requested golden path and relevant edge state through real actions.
   Capture loading, empty, partial, success, failure, recovery, and permission states
   only when they are in scope.
5. Recheck snapshot, screenshot, console, and network after each material transition.
   Use file outputs for large artifacts and filters or pagination for verbose results.
6. Save only evidence needed for the claim. Redact secrets, cookies, personal data,
   tenant identifiers, and unrelated browser state.
7. Report observed behavior separately from inference and proposed remediation.

Do not classify product defects, approve demo readiness, or produce polished media here.
