---
name: firecrawl-web-ingestion
description: Use when governed website or document acquisition is needed for RAG, onboarding, normalization, provenance, embeddings, vector storage, re-ingestion, or evaluation.
---

# Firecrawl Web Ingestion

Treat web acquisition as a governed pipeline. Define the goal, allowed sources, exact scope, tool choice, canonical record, source metadata, storage boundary, review state, and re-ingestion policy before running it.

Prefer `map` for known domains, `scrape` for known pages, `crawl` for bounded sections, `extract` for schema-shaped data, and `agent` only for genuinely broad discovery. Retain source URL, title, fetched time, content hash, authorized audience, and tenant/matter/program scope with each derived chunk.

Read `../../references/product-ingestion-patterns.md` and `../../references/security-and-compliance.md` before acting on sensitive or regulated sources.
