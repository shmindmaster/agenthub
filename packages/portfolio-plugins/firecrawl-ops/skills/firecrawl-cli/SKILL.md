---
name: firecrawl-cli
description: Use the Firecrawl CLI for repeatable search, scrape, map, crawl, interact, parse, monitor, agent, and saved-artifact workflows.
---

# Firecrawl CLI

Use the CLI when the task benefits from reproducible commands, saved JSON/markdown, local file parsing, explicit job status, or a fallback from MCP.

1. Check readiness with `firecrawl --status`; do not print or persist the API key.
2. Authenticate with existing environment or configured CLI state. Prefer `firecrawl login --browser` or `FIRECRAWL_API_KEY`; use `FIRECRAWL_API_URL` for an authorized self-hosted instance.
3. Save large results under a task-local `.firecrawl/` directory and inspect incrementally.
4. Use `search`, `scrape`, `map`, `crawl`, `interact`, `parse`, `monitor`, and `agent` according to `../../references/tool-router.md`.
5. Set limits, path filters, schemas, budgets, polling timeouts, and output formats explicitly. Record rerun inputs and job IDs, not secrets.

The current CLI supports V2 formats including markdown, links, screenshots, JSON, summaries, change tracking, branding, and product data. The deprecated browser shortcut is not the default; scrape first, then interact with the resulting session.
