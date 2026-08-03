---
name: browser-evidence
description: Use when an authorized workflow needs reproducible screenshots, accessibility snapshots, console or network records, Lighthouse results, traces, or screencasts.
---

# Browser evidence

This skill captures observed browser evidence. Product decisions remain with Product
Experience Engineering; demo and release decisions remain with Product Demo Studio.

## Procedure

1. Record build SHA, environment, role, URL, synthetic dataset, locale, timezone,
   viewport, zoom, color scheme, and reduced-motion setting.
2. Use the plugin's isolated headed Chrome profile. Do not expose normal personal
   Chrome state, unrelated tabs, credentials, or customer data.
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
