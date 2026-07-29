---
name: firecrawl-web-ingestion
description: Design and operate governed Firecrawl-based acquisition for RAG, customer onboarding, website/document ingestion, source normalization, provenance, embeddings, vector storage, re-ingestion, and evaluation.
---

# Firecrawl Web Ingestion

Treat web acquisition as a governed pipeline. Define the goal, allowed sources, exact scope, tool choice, canonical record, source metadata, storage boundary, review state, and re-ingestion policy before running it.

Prefer `map` for known domains, `scrape` for known pages, `crawl` for bounded sections, `extract` for schema-shaped data, and `agent` only for genuinely broad discovery. Retain source URL, title, fetched time, content hash, authorized audience, and tenant/matter/program scope with each derived chunk.

Read `../../references/product-ingestion-patterns.md` and `../../references/security-and-compliance.md` before acting on sensitive or regulated sources.
