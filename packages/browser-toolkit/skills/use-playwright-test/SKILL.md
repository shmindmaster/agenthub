---
name: use-playwright-test
description: Use when browser proof should become a reproducible Playwright Test regression — fixtures, locators, assertions, traces — rather than an interactive MCP or CLI exploration session.
---

# Use Playwright Test

<!-- skill-kind: provider-reference -->
<!-- provider-channel: test -->

Official docs: https://playwright.dev/docs/intro

**Do not start here.** This file is the provider catalog for the Playwright Test
lane after a routing skill chose it. Enter through:

- `interactive-browser-testing`
- `browser-debugging`
- `browser-evidence`

Sibling catalogs: `use-playwright-cli` (token-efficient capture),
`use-playwright-mcp` (exploratory MCP).

This lane is **not** an MCP server and does not appear in `registry/mcps.json`.
It is `@playwright/test` in the **target repository** (or a scratch project),
not an AgentHub-owned test runner.

---

## When to use this lane

Prefer **Playwright Test** when:

- interactive exploration already found a **regression worth preserving**
- the deliverable is a **repeatable automated test** (CI, PR checks, local
  `npx playwright test`)
- you need fixtures, web-first assertions, locators, and HTML/trace reports

Do **not** start here for first-look visual QA — use `interactive-browser-testing`
with CLI or MCP first, then promote to Test.

---

## Minimal workflow

1. Confirm the target repo already has Playwright Test, or scaffold only with
   owner approval (`npm init playwright@latest` / package scripts the repo uses).
2. Encode the golden path with locators and web-first assertions; prefer
   role/text/test-id locators over brittle CSS.
3. Capture trace/screenshot on failure via Playwright config, not by dumping
   binaries into AgentHub.
4. Run the focused test; keep customer/PII out of fixtures (synthetic data only).

```powershell
npx playwright test --project=chromium path/to/spec.ts
npx playwright show-report
```

---

## Relationship to other lanes

| Lane | Role |
|---|---|
| CLI (`use-playwright-cli`) | Discover and capture quickly while coding |
| MCP (`use-playwright-mcp`) | Exploratory persistent reasoning |
| Test (this file) | Lock the bug/behavior into CI |

Routing skills should add repository Playwright tests only after discovering a
regression worth preserving. Existing automated tests do not replace interactive
rendered verification.

---

## Anti-patterns

- Treating `@playwright/test` as a fleet MCP id.
- Committing credentials, production dumps, or private screenshots into AgentHub.
- Writing tests before a single interactive reproduction exists.
- Using Test for one-off exploratory clicking (use CLI/MCP).
