# Portfolio architecture policy

Status: proposed revision, awaiting owner approval. This document is a review
baseline, not an instruction to migrate production or activate fleet enforcement.
The owner selected evidence-based revisions, application fixes, and isolation
before dedicated infrastructure. Legal-entity assignments remain provisional.

## 1. Objective and applicability

Optimize for contained failures and reversibility before reuse. Every product
must remain independently releasable, operable, transferable, and retireable.
Default to a modular monolith within each product. Existing web/API/worker
separation is not itself a defect; measure failure domains and scaling needs
before changing deployable units.

This policy governs product architecture and product-facing shared services.
AgentHub and Local-AI are operator capabilities, not an established production
platform for the products. Their private retrieval stores, media runtimes and
client access retain their separate authorization and data boundaries. They are
not candidates for repartitioning through this policy.

Never share client and private-product runtimes, data stores, identity tenants,
or credentials. A common vendor is not a common tenant. Do not infer legal
ownership from a GitHub namespace. Unknown ownership blocks new sharing and
resource migrations; it does not authorize deletion of existing resources.

Offline apps, developer tools, reference projects and retired redirects retain
their appropriate local persistence and release topology. Managed Postgres,
queues, shared auth and horizontal scale are not mandatory features.

## 2. Sharing tiers

| Tier | Definition | Creation bar |
|---|---|---|
| T0 | Copied conventions, examples, scaffold configuration | Copy without runtime dependency; accept drift |
| T1 | Versioned cross-product packages | Three real consumers, stable contract over two releases, pinned versions, named owner and reversal plan |
| T2 | Shared application service or managed infrastructure | Named owner, consumer and entity inventory, bounded data access, recovery/degraded mode, measurable service target, versioned owned interface where applicable, ADR |
| T3 | Shared logical product data, cross-product tables/foreign keys, shared retrieval collection protected only by filters | Prohibited |

The three-consumer threshold governs new extraction, not automatic demolition
of an existing two-consumer service. Same-product workspace packages are not
cross-product T1 packages. Existing sharing is registered as existing-unverified
until its boundary is demonstrated; it is not silently approved or grandfathered.

Managed Postgres clusters, Valkey hosts and object-storage infrastructure are
T2 infrastructure dependencies. One logical database has one product owner;
a product may own separate operational and observability databases. A physical
cluster can host isolated product databases within confirmed ownership, provided
roles cannot access other products, each product can be restored/exported alone,
and the common outage and cost are recorded. Database names alone prove none
of those access or recovery properties.

Postgres grants database CONNECT to PUBLIC by default; named application users
alone are insufficient evidence. Review actual privileges, role memberships and
default grants. See the [Postgres privilege reference](https://www.postgresql.org/docs/current/ddl-priv.html).

Cache database numbers and key prefixes are namespacing, not authorization.
Use scoped credentials/ACLs and product checks. When those controls cannot be
demonstrated, move sensitive durable state into the product's existing database
or design separately authorized dedicated infrastructure. Never delete data to
make an audit green. Record legacy-object compatibility before changing keys.

DigitalOcean currently restricts Valkey ACL commands and does not offer ordinary
backup/restore. Do not promise an ACL-only or backup-based repair on that service
without a supported provider route. See [Valkey limits](https://docs.digitalocean.com/products/databases/valkey/details/limits/).

## 3. Direction, contracts and content

Product-to-platform dependencies may carry runtime traffic. Platform code must
not import product internals, and products must not import each other's source.
An authorized business integration between products uses a producer-owned API
or event and an ADR; it is not permission to read another product's database.
Notifications and callbacks are directed interface calls, not reverse source
dependencies. Reject dependency cycles.

Share transport and machinery only when semantics are stable. Prompts, pricing,
domain rules, retrieval semantics, message composition and product documents
remain product-owned. Notification/model/document services necessarily see
payloads when they process them: classify transit, persistence, logs and provider
retention explicitly. Do not describe them as content-free control planes.
Default to no regulated payload through a shared service. An exception requires
documented data classes, authorized recipients, retention/redaction controls,
entity boundaries and the applicable compliance gate. No compliance attestation
is implied by architecture or by this policy.

Keep retrieval collections or indexes product-owned with scoped access; tenant
filters alone do not establish a product boundary. The rule applies to product
retrieval, not a blanket redesign of separately governed operator knowledge.

Published cross-repository APIs use versioned OpenAPI/typed contracts and
generated clients where supported. Keep compatible versions until consumers
migrate, with an explicit retirement decision. Do not replace vendor SDKs or
same-product clients merely to satisfy a generation slogan.

Use synchronous calls when the outcome is required now or when the workflow
explicitly promises only an immediate attempt. Use durable events when accepted
work must survive failure: producer business state and its outbox event commit
in one transaction; consumers use explicit idempotency keys. Never claim
exactly-once behavior from an outbox alone.

Every T2 dependency has a tested down mode. Safe denial, preserved user input,
bounded retries, local durable queueing and an authorized fallback are all valid.
Identity, payment authorization, audit-required writes and evidence-grounded AI
may fail closed. A fallback must not bypass authorization, lose provenance or
send data to an unapproved provider. A static contact form need not acquire a
database unless it promises durable acceptance. Provider acceptance is not
recipient delivery; uncertainty must remain visible.

## 4. Dependencies, topology and scale

Prefer deleting/configuring a requirement, existing runtime/framework features,
an already-operated provider capability, then a maintained library, then a new
operated service. Evaluate total ownership effort rather than line count alone.
Document replacement within a working week or a specific exception with an exit
plan. Keep one system of record per datum; caches and derived indexes are allowed
when rebuildable, scoped and explicitly non-authoritative. No speculative provider
abstractions or unbounded common/utils packages.

Keep one repository per product. Preserve the existing agent capability owner
in AgentHub. Do not create a platform repository just to satisfy a diagram;
introduce one only when qualifying product platform components need an owner.
Use copied templates and independently adopted version bumps. Revisit topology
only with measured cross-product churn and confirmed common ownership.

Scale against measured latency, errors, queue age/depth, throughput, resource
saturation and per-product idle/usage cost. An arbitrary 10x target does not
justify more services. Verify rate limits, idempotency and background work across
instances before horizontal scaling. Give each product a recovery and retirement
procedure that can be exercised without another product's release.

## 5. Registry, evidence and gates

`registry/capabilities.json` owns agent capabilities, not production service
instances. Its existing `portfolio-engineering` owner maintains the product
roster in `packages/portfolio-engineering/portfolio.json` and the sharing
declarations in the adjacent `architecture.json`. Do not create a second
capability owner or put secrets/customer evidence into either registry.

The architecture declarations record tier, kind, consumers, ownership, status,
SLO, interface, down mode and reversal plan. Unknown values are null, never a
false claim of absence. Operational evidence stays outside Git and records
source SHA, dirty diff, provider observation time, tested scope and blockers.
The declaration checker is not a runtime access test or a complete code scanner.

Require an ADR for new T2 services, external breaking contracts, new cross-product
data flow and dependencies that create a new operational/data boundary. Routine
patch upgrades of an approved library do not each require a new ADR.
Owner review is required for new T2 creation, expansion of existing blast radius,
regulated content crossing a boundary, client/private resource sharing, a new
system of record, destructive migration or reduced reversibility.

Policy activation, production changes, access-control changes and real delivery
tests are separate gates. A blocked change still receives a concrete design,
validation plan and reversal plan; it remains unapplied.

Upon owner approval, insert the concise architecture routing section after
Capability ownership and before Capability routing in the compiled personal
policy. Keep owner/product identifiers out of the public policy core. Validate
the policy projection and registry, then audit the host sync before applying it.
