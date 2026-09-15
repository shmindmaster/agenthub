---
name: firecrawl-web-ingestion
description: Use when governed website or document acquisition is needed for RAG, onboarding, normalization, provenance, embeddings, vector storage, re-ingestion, or evaluation on this fleet.
---

# Fleet Firecrawl ingestion overlay

Live Firecrawl operations (search, scrape, map, crawl, interact, parse, monitor,
agent, and product SDK integration) belong to the official Firecrawl skills and
plugin, not this package.

Install and update from upstream, then apply the fleet constraints below:

```bash
npx skills add firecrawl/skills
# or, for CLI plus core skills:
npx -y firecrawl-cli@latest init
```

Official catalog: https://github.com/firecrawl/skills
Official MCP: `https://mcp.firecrawl.dev/v2/mcp` (already the fleet remote in
`registry/mcps.json`). Do not add a second Firecrawl MCP, and do not copy
official `firecrawl-scrape` / `firecrawl-crawl` skills into AgentHub.

## Fleet constraints

Treat web acquisition as a governed pipeline. Define the goal, allowed sources,
exact scope, tool choice, canonical record, source metadata, storage boundary,
review state, and re-ingestion policy before running it.

Prefer official `map` for known domains, `scrape` for known pages, `crawl` for
bounded sections, structured extract for schema-shaped data, and `agent` only
for genuinely broad discovery. Retain source URL, title, fetched time, content
hash, authorized audience, and tenant/matter/program scope with each derived
chunk.

Read `../../references/product-ingestion-patterns.md` and
`../../references/security-and-compliance.md` before acting on sensitive or
regulated sources. Never expose `FIRECRAWL_API_KEY`.
