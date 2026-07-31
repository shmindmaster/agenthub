---
name: browser-debugging
description: Reproduce and diagnose browser defects through a dedicated Chrome session using DOM, accessibility, console, network, Lighthouse, and performance evidence. Use for authenticated bugs, runtime errors, request failures, layout problems, and performance investigations.
---

# Browser Debugging

## Tool choice

- Prefer the host-native Chrome/browser plugin when it provides the required diagnostics. Otherwise launch Chrome DevTools MCP only through this task-scoped skill path; never add it to global host configuration. Use it for the developer's real, visible QA Chrome state,
  network/response inspection, console/runtime errors, Lighthouse, and
  performance traces.
- Use Hermes native browser for quick ordinary browsing when DevTools depth is
  unnecessary.
- Use repository-owned Playwright when a repeatable regression already exists
  or should be added under repository policy.
- Use Qwen Code Computer Use only for required native UI outside browser APIs.
- On a host without native dynamic MCP tools, launch the dedicated QA Chrome
  profile, then run the canonical
  `capabilities/browser-toolkit/scripts/run-chrome-devtools-task.mjs` with one
  JSON plan. It launches and closes one MCP worker for that plan; do not add a
  host configuration entry.

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
Do not leave a Chrome DevTools MCP worker running after the task-scoped diagnostic session ends.

## UI change completion gate

Never claim a UI change works without rendering the changed flow.

1. Read the repository's current instructions and native startup scripts.
   Never guess the command or port.
2. Capture console and network state before exercising the change, render the
   affected flow, then check both again afterward.
3. Exercise the golden path and one relevant edge case through real
   interactions rather than relying on a static screenshot.
4. When the repository has Playwright coverage, use its actual focused
   configuration and command; do not assume the default config filename.
5. Capture a screenshot of the verified result.
6. If the application cannot be rendered in the available environment, report
   the exact environment blocker and do not substitute type-checking, unit
   tests, or source inspection for browser evidence.

This completion gate does not replace the separate browser-evidence skill or
Product Demo Studio's capture and release decisions.
