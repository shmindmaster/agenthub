# Test strategy

| Layer | Required proof |
| --- | --- |
| Smoke | Controlled page, snapshot, fill/click/submit outcome, screenshot, console/network, Lighthouse |
| Core E2E | Repository-owned deterministic critical workflows and persisted business outcomes |
| Role/permission | Distinct synthetic identities, allow/deny outcomes, no cross-tenant leakage |
| Failure/recovery | Loading, empty, stale/partial, validation, request failure, retry, recovery |
| Visual | Representative workflow states across required viewports, zoom, themes, reduced motion |
| Accessibility | Accessible names, keyboard path, focus, announcements, contrast, zoom, automated checks |
| Responsive | Narrow/wide mobile, tablet, laptop, desktop, wide desktop |
| Performance | DevTools LCP/INP/CLS, long tasks, waterfalls, duplicate/failed requests, throttling |
| Demo | Current readiness handoff, reset/seed, truth sheet, clean source, manifests, claim ledger, final QA |
| Cross-browser | Repository-owned Chromium/Firefox/WebKit where technically applicable |
| CI | Headless deterministic tests; no authenticated personal profile or desktop automation |

Keep failure traces/screenshots/videos and release evidence long enough for the
repository's review cycle. Keep approved demo provenance and checksums with the
release package. Raw captures stay gitignored. Baseline updates require a named
reviewer, the intended UI change, representative-state review, and a clean
rerun; never auto-accept diffs.
