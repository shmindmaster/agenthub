# Portfolio intelligence direction

This is a proposed direction for research-enabled commercial and product work.
Each product's repository instructions, Linear acceptance criteria and release
decisions govern its execution. Verify current code and production state before
presenting an integration as implemented or deployed.

AgentHub provides development-time access to Exa, Parallel and Tavily through
their supported native integrations. Production workflows use their own
authorized server-side provider connections and product-specific controls.

## Commercial research

Start with ABACare's existing founder pipeline and
[SH-3805](https://linear.app/shorg/issue/SH-3805). Discover and verify public
business identities, deduplicate against the existing
[SH-1334 pipeline](https://linear.app/shorg/issue/SH-1334), and record source
evidence, unknown fields, product fit, owner and outreach state. Keep proposed
messages reviewable and measure cost per usable lead. ABACare work uses the
ABACare AI LLC identity. Confirm the appropriate entity, account and data
permissions independently for other products.

Reuse research methods for marketing and customer preparation. Ground public
product claims in verified release evidence and distinguish proposed,
implemented, tested and deployed capabilities.

## Product opportunities

These are candidates for evaluation within existing product priorities.

| Product | Candidate research use |
| --- | --- |
| ABACare | Public payer-policy change review and independent clinic discovery |
| CoLedger | Public sponsor and portfolio-company briefs |
| Revolva | Official country-pair and mobility guidance |
| Empowera | External guidance changes and proposed SOP impact |
| LienWise | Jurisdiction source updates and construction-law research |
| SubOps | Public carrier guidance and contractor research |
| Lawli | Official court forms and procedural updates |
| LexAlign | Source-grounded authority research for claim review |
| GentleNext | Community resource discovery and freshness |

ABACare's [SH-2296](https://linear.app/shorg/issue/SH-2296) owns payer-source
monitoring and impact work. Reuse its source registry and review workflow and
investigate the inaccessible source under
[SH-4899](https://linear.app/shorg/issue/SH-4899). Assess provider changes
against the current product implementation and approved source access.

CoLedger buyer validation remains governed by
[SH-1221](https://linear.app/shorg/issue/SH-1221) and its
[SH-4240 decision gate](https://linear.app/shorg/issue/SH-4240). Revolva's
first paid workflow remains under
[SH-3520](https://linear.app/shorg/issue/SH-3520). Product-specific data,
approval, legal and clinical requirements remain with their owners.

## Shared production capability

Start with reusable contracts and a small server-side client library for the
first validated workflow. Add a deployed API or worker only when two distinct
workflows demonstrate a need for shared scheduling, monitoring or job
operations. Use durable job identity, progress, bounded retries, provider
references, usage, cost and failure state when lengthy processing requires it.
Keep source and fact records portable across providers.
Applications retain their customer data, permissions, business rules and
decisions.

Evidence records should carry source identity and URL, publisher,
jurisdiction, publication and effective dates, retrieval time, content version
or hash, supporting passage, provider and job, extracted facts, conflicts,
verification state, reviewer, decision and tenant scope. Apply appropriate
retention and deletion rules. Treat retrieved pages as untrusted data.

Before production use, demonstrate isolation across application, tenant and
environment, including negative authorization tests. Test retries,
deduplication, job recovery, observability and product review flows. Use the
portfolio's durable storage, backup and recovery standard. Establish relevant
agreements and permissions before sending sensitive data to a provider.

## Evaluation and monitoring

Benchmark engineering research and run the Texas ABA discovery pilot first.
Compare providers on representative work before making routing decisions.
Use 30–50 engineering questions, 50–100 independently verified entities and
a controlled set of historical changes. Record factual and citation accuracy,
coverage, latency and cost, plus entity-field accuracy, missed changes and
false alerts. Record unavailable or unauthorized provider capabilities
separately from failed evaluations.

After a use case proves valuable, consider bounded monitoring for event or
structured snapshot changes. Record the old and new evidence, source date,
effective date where known, affected product, uncertainty and review status.
A reviewed change may create a proposed follow-up in the relevant product's
existing workflow. Establish provider account, budget and monitoring cadence
for that use case.

## Sources

- [Exa documentation](https://docs.exa.ai)
- [Parallel documentation](https://docs.parallel.ai)
- [Tavily documentation](https://docs.tavily.com)
- [Portfolio product standard](../../packages/product/references/portfolio-standard.md)
