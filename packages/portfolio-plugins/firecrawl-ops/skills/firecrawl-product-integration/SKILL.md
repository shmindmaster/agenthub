---
name: firecrawl-product-integration
description: Implement Firecrawl SDK or API integrations in application backends, workers, queues, RAG pipelines, and agent tools with provenance, isolation, retries, and secure environment configuration.
---

# Firecrawl Product Integration

Integrate through a narrow server-side client, never directly from a UI component. Use product-specific methods, run long jobs in workers, persist normalized source data before embedding, and enforce the application's tenant/matter/program scope for storage and retrieval.

Validate structured extraction, use idempotency based on source URL plus content hash, log without source content or secrets, and test empty content, retryable errors, schema mismatch, duplicates, provenance, and cross-scope access denial.

Read `../../references/product-ingestion-patterns.md` and `../../references/security-and-compliance.md` first.
