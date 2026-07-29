---
name: firecrawl-batch-scrape
description: Run asynchronous Firecrawl batch scrapes for a known URL set with status, error, cancellation, and provenance handling.
---

# Firecrawl Batch Scrape

Use batch scrape when the URL set is already known and parallel asynchronous processing is more useful than discovery. Validate and deduplicate the input list, choose formats/schema, set a bounded scope, retain the job ID, poll status, inspect batch errors, and cancel abandoned jobs. Store each result with its URL, fetched time, content hash, and extraction method; do not treat a completed job as proof that every URL succeeded.
