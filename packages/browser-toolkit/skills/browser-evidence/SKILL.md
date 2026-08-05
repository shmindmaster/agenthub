---
name: browser-evidence
description: Use when an authorized workflow needs reproducible screenshots, accessibility snapshots, console or network records, Lighthouse results, traces, or screencasts.
---

# Browser evidence

This skill captures observed browser evidence. Product decisions remain with Product
Experience Engineering; demo and release decisions remain with Product Demo Studio.

## Capability required

This skill requires `browser.isolated`, defined in `registry/fleet-profile.json`
under `hostSurfaces.capabilityMeanings` as: "A first-party browser the agent drives
itself, with its own profile. Suits localhost and public pages; carries no signed-in
session."

Isolation is the point here, not an implementation detail: evidence must not carry
personal Chrome state, unrelated tabs, credentials, or customer data.

## Resolve a provider before capturing

1. Look up the running surface in `registry/fleet-profile.json`,
   `hostSurfaces.surfaces`. If it records the required capability as `true`, capture
   with its own first-party browser and start nothing.
2. Use `chrome-devtools` -- the declared fallback, `providesCapabilities` in
   `registry/mcps.json` -- when the surface records `false` or `null`, or when the
   evidence needed is a performance trace, heap comparison, or Lighthouse run.

`false` and `null` are different findings and neither is a provider: `false` means
checked and absent, `null` means never established. Record which provider produced
each artifact, because a screenshot's meaning depends on the profile it came from.

Native first is not a quality judgement. `registry/mcps.json`, `activationPolicy`
requires a local server to be started by the capability that needs it rather than at
session start, and to run as one shared process rather than one per host.
`chrome-devtools` is the most widely declared local process in the fleet
(`localProcessPolicy.declaredByHostCount`), and every host that spawns its own `npx`
instance costs a separate browser-driving process, so a session that resolves
natively must not start one it never uses.

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
