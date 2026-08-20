---
name: browser-debugging
description: Use when an authorized browser workflow has runtime errors, failed requests, accessibility defects, memory growth, or unexplained performance behavior.
---

# Browser debugging

For MCP tool names and the core loop, also load **`use-playwright-mcp`**.

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A browser the agent drives itself with a throwaway or per-workspace profile,
carrying no signed-in session. Suits localhost and public pages. This is the
capability that scales across hosts, because no two sessions contend for one
profile directory -- Playwright MCP partitions automatically as
mcp-{channel}-{workspace-hash}, and --isolated removes the on-disk profile
entirely."

It also requires DevTools-protocol depth: performance traces, heap snapshots,
Lighthouse, and raw console/network correlation. That depth is not a capability name
in `hostSurfaces` because only one provider offers it, and a capability name nothing
else resolves is vocabulary rather than routing. It is the actual justification for
the local `playwright` fallback, so this skill reaches it more often than the
other two when DevTools depth is required.

## Resolve a provider before choosing a tool

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, drive its
   own first-party browser for observation, reproduction, and accessibility work.
   Nothing extra is started.
   <!-- resolution-step: surface-provided -->
2. Use `playwright` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` for `browser.isolated` -- when the surface records `false` or
   `null`, or when the step needs DevTools depth the surface cannot reach.
   <!-- resolution-step: local-fallback -->
3. Use Playwright CLI only when compact repeatable actions are more useful than live
   DevTools state.
   <!-- resolution-step: additional-lane -->

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. Resolve, do not assume.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`playwright` is the QA fallback for this skill; do not start it when
the surface already provides `browser.isolated`. Its profile is separate from
personal Chrome, which is the isolation this skill requires.

## Workflow

1. Record the build, URL, role, synthetic identity, viewport, and reproduction.
2. List the resolved provider's open pages, select the target page, wait for the
   expected state, then take both a snapshot and screenshot. Refresh the snapshot
   after DOM changes.
3. Reproduce with natural clicks, typing, hover, focus, and keyboard navigation.
4. Correlate visible state with console messages and network requests. Inspect only
   relevant request details and redact credentials, cookies, tokens, and private data.
5. For accessibility, compare the accessibility snapshot with the screenshot; check
   headings, accessible names, labels, focus order, modal focus trapping, keyboard
   operation, tap targets, and contrast. Use Lighthouse as a baseline, not sole proof.
6. For performance, capture a normal trace before justified throttling. Report the
   observed LCP, INP, CLS, long tasks, blocking resources, and request waterfall.
7. For suspected leaks, capture baseline and post-repetition heap snapshots, compare
   summaries and retaining paths, then close every loaded snapshot. Never read a raw
   heap snapshot into model context.
8. Use reversible live CSS or JavaScript only to test a hypothesis. The repository fix
   and focused regression remain the deliverable.

Do not enable experimental tool categories or attach to personal Chrome for this skill's
`browser.isolated` path. The automation profile is not personal Chrome, so the default
mode already satisfies that requirement; attaching to a live personal session would mean
passing `--browserUrl` deliberately, which is outside this skill.' Do not call type checks or unit tests browser proof.
