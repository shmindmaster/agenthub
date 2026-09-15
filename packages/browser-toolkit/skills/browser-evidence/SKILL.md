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
- `use-playwright-cli` — named-session screenshots, traces, and **session video**
- `use-playwright-test` — fixture-backed evidence inside a regression suite when appropriate
- `desktop-evidence` — native Windows window or whole-desktop stills and recordings

A URL or web app stays here. A native window or the whole desktop is
`desktop-evidence`, not a browser screenshot.

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

1. If the target is a native Windows window or the whole desktop, load
   `desktop-evidence` and stop. Do not capture that target through a browser.
   <!-- resolution-step: additional-lane -->
2. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, capture
   with its own first-party browser and start nothing.
   <!-- resolution-step: surface-provided -->
3. Use `playwright` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` for `browser.isolated` -- when the surface records `false` or
   `null`, or when the evidence needed is MCP-side console/network/snapshot capture.
   Load `use-playwright-mcp`.
   <!-- resolution-step: local-fallback -->
4. Session video and Playwright traces MUST use Playwright CLI
   (`video-start` / `video-stop`, `tracing-start` / `tracing-stop`). Load
   `use-playwright-cli`. Fleet Playwright MCP does not pass `--caps=devtools`,
   so MCP has no video or trace tools. Do not enable that cap fleet-wide.
   <!-- resolution-step: additional-lane -->
5. Use Playwright Test when evidence belongs inside a committed regression run.
   Load `use-playwright-test`.
   <!-- resolution-step: additional-lane -->

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. An unlisted surface is `null`,
not absent. `registry/mcps.json` `hostScopeNote` is MCP deployment eligibility, not
this matrix. A Chrome or Edge extension present on disk is not
`browser.authenticated`; that value is true only when this surface records a
connected session. Record which provider produced each artifact, because a
screenshot's meaning depends on the profile it came from.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the MCP QA fallback for this skill; do not start it when the surface
already provides `browser.isolated`. Its dedicated profile is separate from personal
Chrome, so evidence captures are isolated by construction. Attaching to the owner's
live personal Chrome would require a browser-url attachment deliberately and must not
be done for evidence captures.

Microsoft Playwright MCP does not expose retired Chrome DevTools MCP Lighthouse or
screencast tools. Prefer Playwright screenshots and snapshots on MCP; prefer
Playwright CLI for traces and session video. Use a dedicated audit tool only when
Lighthouse-style scores are explicitly required.

Write files under the evidence root owned by `desktop-evidence`'s helper:

```text
%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\
```

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
6. Save only evidence needed for the claim under the evidence root above. Redact
   secrets, cookies, personal data, tenant identifiers, and unrelated browser state.
   Do not commit capture blobs to a repository.
7. Report observed behavior separately from inference and proposed remediation.

Do not classify product defects, approve demo readiness, or produce polished media here.
