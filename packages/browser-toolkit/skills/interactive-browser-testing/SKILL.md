---
name: interactive-browser-testing
description: Use when a coding agent should visually inspect and interact with a real browser workflow instead of relying only on automated Playwright tests or source inspection.
---

# Interactive browser testing

## Choose the lane

- Use Chrome DevTools MCP for exploratory testing, screenshots plus model vision,
  accessibility snapshots, console/network correlation, Lighthouse, performance,
  screencasts, or memory analysis.
- Use pinned Playwright CLI for token-efficient action sequences, multiple named
  sessions, screenshots, traces, video, or locator generation:

```powershell
npx -y @playwright/cli@0.1.17 -s=<task-slug> open <url> --headed
npx -y @playwright/cli@0.1.17 -s=<task-slug> show --annotate
```

- Add repository Playwright tests only after discovering a regression worth preserving.
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

The MCP plugin uses a temporary isolated Chrome profile. Connecting to an already-running
Chrome profile requires explicit authorization and Chrome remote debugging; never attach
to ordinary personal browsing by default.
