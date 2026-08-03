# Security and Compliance

- Never print, persist, or commit `FIRECRAWL_API_KEY`.
- Keep calls server-side; do not expose credentials in browser code.
- Confirm authorization and terms before crawling authenticated, customer, regulated, or evidence sources.
- Keep bounded source scope and capture provenance for every derived record.
- Do not auto-apply high-impact changes from monitored sources; queue human review.
