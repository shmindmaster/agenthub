# Firecrawl Tool Router

Official Firecrawl skills own live tool choice. Install
`npx skills add firecrawl/skills` (or `npx -y firecrawl-cli@latest init`) and
follow those skills. This page is the fleet reminder of the smallest surface,
not a fork of the upstream catalog.

Use the smallest Firecrawl V2 surface that can produce the requested evidence. The MCP server is the preferred tool surface; use the CLI when a saved artifact, repeatable command, local-file parse, or explicit job polling is useful.

- `firecrawl_search`: discover current facts, news, companies, papers, or unknown sources. Start with 3-5 results and use time/location/source filters when relevant.
- `firecrawl_scrape`: extract one known URL into markdown, links, screenshots, JSON, change tracking, or a known schema.
- `firecrawl_map`: discover URLs on a known domain before selecting pages or crawling.
- `firecrawl_crawl`: bounded multi-page extraction after mapping; apply path filters and low limits first, then poll status.
- `firecrawl_batch_scrape`: scrape a known list of URLs as an asynchronous job; retain the job ID and inspect errors.
- `firecrawl_extract`: structured extraction from known URLs when the record schema is stable.
- `firecrawl_parse`: convert a local document to LLM-ready data. A remote hosted MCP cannot read local paths directly; use local MCP or its upload handoff.
- `firecrawl_interact`: only after scrape when clicks, forms, pagination, login, or JS-only state is required; stop sessions when finished.
- `firecrawl_agent`: prompt-to-data discovery when URLs are unknown or scattered; use a schema, `maxCredits`, completion polling, and cancellation where needed.
- Research Index tools: use paper/GitHub research endpoints for literature, technical reports, and code-history questions when available.
- Monitor tools: list existing monitors before changing them; scope URL, cadence, retention, notification, and human review.

Escalation: search -> scrape -> map -> bounded crawl/batch -> interact or agent. Do not crawl an entire domain for a known page, run broad jobs without budgets, or place secrets in URLs, logs, or output.
