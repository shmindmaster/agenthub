---
name: browser-debugging
description: Reproduce and diagnose browser defects through a dedicated Chrome session using DOM, accessibility, console, network, Lighthouse, and performance evidence. Use for authenticated bugs, runtime errors, request failures, layout problems, and performance investigations.
---

# Browser Debugging

## Tool choice

- Use Chrome DevTools MCP for the developer's real, visible QA Chrome state,
  network/response inspection, console/runtime errors, Lighthouse, and
  performance traces.
- Use Hermes native browser for quick ordinary browsing when DevTools depth is
  unnecessary.
- Use repository-owned Playwright when a repeatable regression already exists
  or should be added under repository policy.
- Use Qwen Code Computer Use only for required native UI outside browser APIs.

## Procedure

1. Record build, URL, role, synthetic test identity, and exact reproduction.
2. Take a snapshot and screenshot before changing state.
3. Reproduce with the fewest natural interactions.
4. Correlate UI transitions with console messages and network requests.
5. Inspect request method, URL, status, timing, and redacted response content.
6. For performance, capture a trace under normal conditions, then repeat with
   justified CPU/network throttling. Report LCP, INP, CLS, long tasks, blocking
   resources, duplicate/failed requests, and request waterfalls when available.
7. Check hydration warnings, React errors, source-mapped exceptions, and layout
   shifts. Use memory inspection only when stable tooling supports it and the
   hypothesis warrants it.
8. Make reversible live CSS/JavaScript experiments only to validate a
   hypothesis. Do not report them as product fixes.
9. Identify root cause, evidence, affected scope, and a focused regression.

Do not enable experimental Chrome DevTools MCP flags without explicit
authorization, a written reason/risk, and a non-experimental fallback.
