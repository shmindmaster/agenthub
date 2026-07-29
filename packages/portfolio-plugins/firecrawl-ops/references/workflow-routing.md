# Workflow Routing

Use this reference with `firecrawl-workflows` to choose a deliverable-oriented skill. Keep the target repository, product, customer, or market as an input rather than baking project-specific assumptions into the workflow.

| Request shape | Prefer | Deliverable |
| --- | --- | --- |
| Current docs, technical landscape, policy, or YC/RFS fit | `firecrawl-deep-research`, `firecrawl-market-research`, `firecrawl-research-papers` | cited report with evidence, uncertainty, and rerun inputs |
| First customers, ICP, prospects, design partners, or company lists | `firecrawl-lead-research`, `firecrawl-lead-gen`, `firecrawl-company-directories` | qualified lead/company brief or structured list |
| Product readiness, live launch, deployed app, flows, or regression concerns | `firecrawl-qa`, `firecrawl-demo-walkthrough` | evidence-backed QA/readiness report with repro steps |
| Competitor pricing, features, changelogs, or positioning | `firecrawl-competitive-intel` | comparison and change report with dates and sources |
| Docs, portfolio context, RAG, mirrors, or source corpus | `firecrawl-knowledge-base`, `firecrawl-knowledge-ingest` | normalized source inventory and LLM-ready corpus plan |
| Dashboard, internal web tool, or authenticated portal | `firecrawl-dashboard-reporting`, `firecrawl-knowledge-ingest` | scoped extraction with authorization and freshness notes |
| Demo, UX teardown, visual reference, or design system | `firecrawl-demo-walkthrough`, `firecrawl-website-design-clone` | flow walkthrough, UX findings, or agent-ready design brief |
| Product research or shopping comparison | `firecrawl-shop` | sourced comparison and recommendation constraints |
| Site structure and discoverability | `firecrawl-seo-audit` | sitemap, on-page findings, SERP comparison, priorities |

For repository operations, Firecrawl supplies external evidence only. Local Git state, CI, deployment state, credentials, and production/customer proof remain separate verification gates. Never claim a merge, deploy, release, or customer result from web evidence alone.
