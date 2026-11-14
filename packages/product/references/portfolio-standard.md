# Portfolio product and architecture standard

Owner direction, 13 November 2026. Applies to every current and future product in the portfolio. A repository's own `AGENTS.md`, docs and tests stay authoritative for that product; this standard guides choices and audits, it does not override a repository's documented rules.

## 1. Production-grade products, truthful claims

Every product is a complete application meant for real customers, real workflows and persistent customer data. Synthetic data and demo environments are capabilities inside the product, not what the product is.

- Remove wording, docs and assumptions that wrongly call a product synthetic-only, demo-only, a prototype, a mock or a temporary showcase. Where such a description is still true for a product or feature, keep it until the work is actually done.
- Never present unfinished, simulated or unvalidated features as working production functionality. Record three things separately: the intended architecture, what is actually implemented, and demo fixtures. Keep truthful disclosures where they matter.
- A feature shown with synthetic data does not make the product a prototype.

Every applicable product supports real customer organisations and isolated demo tenants; persistent, production-quality data models; secure authentication, authorisation and tenant isolation; complete workflows rather than simulations; reliable APIs, background processing and integrations where needed; production deployment, monitoring, security and recovery; and dedicated demo tenants with realistic synthetic data for demos, testing, training and videos.

## 2. Web, mobile, API and workers

- **Web:** every product with a user interface has a responsive web app with strong UX, accessibility and performance.
- **Mobile:** build Android and iOS apps only where real workflows need them (native device features, offline use, notifications, field work). Prefer a cross-platform stack when it gives the best trade-off. A care product used by practitioners and caregivers in the field is an example that needs them. Do not build a mobile app for portfolio consistency; use responsive web or a PWA where that serves users.
- **Backend APIs:** business logic, authentication, authorisation, persistence and integrations live in backend services. Web and mobile share domain logic and APIs instead of duplicating them.
- **Workers:** run scheduled tasks, document processing, AI inference and agent workflows, ingestion and sync, notifications, long-running jobs and integration retries outside the request path. Choose service boundaries from real operational needs; no microservices for their own sake.

## 3. Persistent storage

- Every app with durable state has a designed persistence layer. Never keep authoritative production data in local containers, ephemeral filesystems or sandbox storage.
- Use durable managed (or properly operated) databases and object storage, reachable only by the app's authorised runtime services.
- Provide migrations and schema versioning, backups with retention and tested recovery, tenant-scoped access control, integrity and concurrency safeguards, and separate production, staging, development and demo data.
- Shared infrastructure never means shared unrestricted data: keep application, organisation, tenant and environment isolation strict.
- Prefer PostgreSQL for transactional workloads unless another database has a justified advantage.

## 4. RAG, semantic search and vectors

Only for products with a real retrieval need. Prefer pgvector on the existing PostgreSQL; use a dedicated vector database only when scale, retrieval quality or missing capabilities justify it. Retrieval is permission-aware, tenant-isolated, observable and privacy-compliant.

## 5. Caching and Valkey

Do not add a Redis-compatible store by default. Early products run well on PostgreSQL, good queries and indexes, application-level caching and database-backed jobs. When a dedicated key-value store is actually needed (shared caching, rate limiting, ephemeral coordination), Valkey is the preferred choice. Add infrastructure in response to measured need, not because mature SaaS stacks have it.

## 6. Marketing sites are static

Marketing sites, landing pages and public information pages are pre-rendered static sites on a CDN, optimised for speed, search, accessibility, responsive design and low cost. Dynamic features, authenticated workflows, databases and sensitive operations stay in the application and its backend. No always-on server just to serve marketing content.

## 7. Transactional email

Every applicable product sends reliable transactional email: invitations, authentication messages, notifications and operational mail.

- **Choose the provider by compliance need.** Resend is the default for ordinary transactional email, including for new products choosing a provider. Email that carries protected health information, or other regulated data, must use a provider that signs the required agreement (for PHI, a HIPAA Business Associate Agreement). Resend does not offer a BAA, so a healthcare product that emails patient information to parents or guardians uses a BAA-covered provider. Keep each product on the provider its compliance needs; do not standardise one provider across products that have different obligations.
- **Resend domain capacity** (for products that use Resend): inventory the registered domains and the account's domain allowance; map each domain to its product; check verification, DNS and sending use; find unused, obsolete or duplicate domains; consolidate sender identities on verified domains and subdomains where supported. Never delete or reconfigure an active sending domain without checking its dependencies and getting the owner's approval.
- Use a consistent sender-domain naming scheme so each product gets a sender identity without unnecessary domain registrations.
- Keep API keys in secret stores; configure SPF, DKIM and DMARC; monitor delivery; handle bounces and complaints.

## 8. Shared patterns, not shared complexity

Reuse proven patterns for authentication and tenant isolation, API design and validation, database access and migrations, durable jobs, AI orchestration and model integration, object storage, email, logging and observability, testing and CI/CD, security, accessibility and performance. Do not force every product into identical infrastructure, one codebase or a distributed architecture. Choose the simplest architecture that safely supports real customers and can grow.

## 9. Audit and remediation

When auditing a product against this standard, check its repository, Linear project, specifications, deployment configuration and public descriptions for: demo-only assumptions, missing production persistence, ephemeral storage holding authoritative data, incomplete API or worker architecture, missing mobile support where workflows justify it, unnecessary infrastructure or caching, marketing sites running avoidable servers, missing or misconfigured email (including the wrong provider for regulated data), unused Resend domains, inconsistent deployment and security, and gaps between documented claims and the implementation.

Record meaningful remediation as Linear issues with implementation detail, dependencies and testable acceptance criteria. Do not redo finished work or rebuild working systems without a reason. Fix genuine production blockers and material product gaps before cosmetic standardisation.

## 10. Governing principle

We build real, differentiated, production-grade products, not collections of demos. Demo tenants, synthetic data, walkthroughs and videos show real capability. Architecture supports real customers from the start without paying for infrastructure sized for thousands of customers we do not have yet.

Optimise for: production readiness, exceptional UX, durable data, secure architecture, operational simplicity, efficient scaling and product differentiation.