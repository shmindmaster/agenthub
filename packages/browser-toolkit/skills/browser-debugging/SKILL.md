---
name: browser-debugging
description: Use when an authorized browser workflow has runtime errors, failed requests, accessibility defects, unexpected traces, or unexplained performance behavior.
---

# Browser debugging

After resolving a provider lane, load the matching catalog:

- `use-playwright-mcp` — live console/network/snapshot correlation (usual debug lane)
- `use-playwright-cli` — compact reproduction scripts, traces, and session video while coding
- `use-playwright-test` — preserve a regression once the failure is understood

If the target is a native Windows window or the whole desktop, load
`desktop-evidence` instead.

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A browser the agent drives itself with a throwaway or per-workspace profile,
carrying no signed-in session. Suits localhost and public pages. This is the
capability that scales across hosts, because no two sessions contend for one
profile directory -- Playwright MCP partitions automatically as
mcp-{channel}-{workspace-hash}, and --isolated removes the on-disk profile
entirely."

It also needs deep runtime observation: console and network correlation, traces,
and accessibility structure. That depth is not a separate capability name in
`hostSurfaces` because only the Playwright MCP/CLI/Test stack offers it here, and
a capability name nothing else resolves is vocabulary rather than routing. It is
the justification for leaving the surface browser when it cannot expose those
signals.

## Resolve a provider before choosing a tool

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, drive its
   own first-party browser for observation, reproduction, and accessibility work.
   Nothing extra is started.
   <!-- resolution-step: surface-provided -->
2. Use `playwright` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` for `browser.isolated` -- when the surface records `false` or
   `null`, or when the step needs MCP-depth console/network/snapshot correlation the
   surface cannot reach. Load `use-playwright-mcp`.
   <!-- resolution-step: local-fallback -->
3. Use Playwright CLI when a compact repeatable reproduction or trace capture is more
   useful than a live MCP reasoning loop. Load `use-playwright-cli`.
   <!-- resolution-step: additional-lane -->
4. After the failure is understood, encode it as Playwright Test when it is worth
   preserving. Load `use-playwright-test`.
   <!-- resolution-step: additional-lane -->

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. An unlisted surface is `null`,
not absent. `registry/mcps.json` `hostScopeNote` is MCP deployment eligibility, not
this matrix. A Chrome or Edge extension present on disk is not
`browser.authenticated`; that value is true only when this surface records a
connected session. Resolve, do not assume.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the MCP QA fallback for this skill; do not start it when the surface
already provides `browser.isolated`. Its profile is separate from personal Chrome,
which is the isolation this skill requires.

### Honest tool expectations

Microsoft Playwright MCP exposes console, network, snapshots, and screenshots.
Fleet config does not pass `--caps=devtools`, so MCP has no video or trace tools;
load `use-playwright-cli` for those. It does not expose retired Chrome DevTools MCP
Lighthouse or heap-snapshot tool names. For Lighthouse-style audits or heap
workflows, use Playwright Trace/CLI/Test or a dedicated audit tool; do not invent
DevTools MCP calls against `playwright`.

## Workflow

1. Record the build, URL, role, synthetic identity, viewport, and reproduction.
2. List the resolved provider's open pages/tabs, select the target, wait for the
   expected state, then take both a structural snapshot and a screenshot. Refresh the
   snapshot after DOM changes.
3. Reproduce with natural clicks, typing, hover, focus, and keyboard navigation.
4. Correlate visible state with console messages and network requests. Inspect only
   relevant request details and redact credentials, cookies, tokens, and private data.
5. For accessibility, compare the accessibility snapshot with the screenshot; check
   headings, accessible names, labels, focus order, modal focus trapping, keyboard
   operation, tap targets, and contrast.
6. For performance, capture a normal Playwright trace before justified throttling.
   Report observed load behavior, long tasks, blocking resources, and request
   waterfall from that evidence.
7. Use reversible live CSS or JavaScript only to test a hypothesis. The repository fix
   and focused regression remain the deliverable.

Do not enable experimental tool categories or attach to personal Chrome for this skill's
`browser.isolated` path. The automation profile is not personal Chrome, so the default
mode already satisfies that requirement; attaching to a live personal session would mean
passing a browser-url attachment deliberately, which is outside this skill. Do not call
type checks or unit tests browser proof.
