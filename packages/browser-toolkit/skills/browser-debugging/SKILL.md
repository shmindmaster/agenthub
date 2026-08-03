---
name: browser-debugging
description: Use when an authorized browser workflow has runtime errors, failed requests, accessibility defects, memory growth, or unexplained performance behavior.
---

# Browser debugging

Use Chrome DevTools MCP for deep inspection. Use Playwright CLI only when compact
repeatable actions are more useful than live DevTools state.

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
without explicit authorization. Do not call type checks or unit tests browser proof.
