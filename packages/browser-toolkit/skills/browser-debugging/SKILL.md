---
name: browser-debugging
description: Use when an authorized browser workflow has runtime errors, failed requests, accessibility defects, memory growth, or unexplained performance behavior.
---

# Browser debugging

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A first-party browser the agent drives
itself, with its own profile. Suits localhost and public pages; carries no signed-in
session."

It also requires DevTools-protocol depth: performance traces, heap snapshots,
Lighthouse, and raw console/network correlation. That depth is not a capability name
in `hostSurfaces` because only one provider offers it, and a capability name nothing
else resolves is vocabulary rather than routing. It is the actual justification for
`chrome-devtools`, so this skill reaches the fallback more often than the other two.

## Resolve a provider before choosing a tool

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, drive its
   own first-party browser for observation, reproduction, and accessibility work.
   Nothing extra is started.
2. Use `chrome-devtools` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` -- when the surface records `false` or `null`, or when the
   step needs DevTools depth the surface cannot reach.
3. Use Playwright CLI only when compact repeatable actions are more useful than live
   DevTools state.

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. Resolve, do not assume.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`chrome-devtools` is the most widely declared local process in the fleet
(`localProcessPolicy.declaredByHostCount`), and every host that spawns its own `npx`
instance costs a separate browser-driving process, so a session that resolves
natively must not start one it never uses.

## Workflow

1. Record the build, URL, role, synthetic identity, viewport, and reproduction.
2. Use `list_pages`, select the target page, wait for the expected state, then take
   both a snapshot and screenshot. Refresh the snapshot after DOM changes.
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

Do not enable experimental tool categories or connect to a personal Chrome profile
without explicit authorization. A signed-in browser profile is a separate capability
this skill does not request and must not obtain by other means. Do not call type
checks or unit tests browser proof.
