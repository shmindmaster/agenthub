# Governed Web Ingestion

Use Firecrawl behind a server-side service boundary. Store source URL, fetched time, content hash, extraction method, authorization state, and tenant or matter scope before embedding or reuse.

For a new ingestion flow, specify source allow-lists, discovery and extraction tools, canonical record schema, storage location, isolation predicate, re-ingestion policy, human-review states, and tests for empty content, retries, duplicates, provenance, and cross-tenant denial.

Use `map` before large crawls, apply include/exclude path filters, and treat regulated, customer, legal, healthcare, and financial content as review-gated.
