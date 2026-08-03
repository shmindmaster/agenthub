---
name: firecrawl-crawl
description: Use when content must be collected from multiple related pages with explicit scope, path filters, job polling, and error review.
---

# Firecrawl Crawl

Use `firecrawl_crawl` or `firecrawl crawl` only after defining the domain, allowed paths, page limit, depth, output format, and review boundary. Prefer map plus selected scrape when only a few pages are needed. For asynchronous crawls, retain the job ID, poll status, inspect errors, and cancel over-broad jobs. Store source metadata with every derived page and never use a broad crawl to infer customer, legal, healthcare, or financial facts without review.
