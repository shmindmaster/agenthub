# Portfolio improvement execution

## Outcome and constraints

Implement the portfolio plan through tested, independently reviewed changes and verified releases. The owner authorized continued implementation, commits, integration and deployment on 2026-09-09 without further approval requests, including necessary breaking changes. Preserve unrelated changes, data, product lifecycle constraints and security boundaries. Use existing portfolio-engineering ownership. Exclude private portfolio-records and client repositories from reports and indexing. This authorization does not turn failed tests or unknown runtime state into release evidence.

## Tasks

1. Extend portfolio-engineering with explicit inventory, evidence/finding/execution contracts, safe local collection and validation, Renovate preparation, structural checks, and local reporting. Fix security-hook missing-scanner behavior with failure fixtures.
2. Fix SubOps notification recovery, recipient validation, durable public-waitlist notices, and stale runtime documentation; test recovery and duplicate suppression.
3. Isolate ABACare tenancy changes; reproduce FORCE-RLS migration inconsistency with disposable PostgreSQL, reconcile migration lineage, validate application-role isolation, and fix demonstrated guide contradictions.
4. Repair Local-AI retrieval interpreter through the provisioner; add bounded interpreter health validation, diagnose embedding service independently, and verify profile-filtered retrieval.
5. Fix SHTrial parsed redirect contract and stale guidance while preserving retirement; reconcile Lawli guide contradictions.
6. Collect the complete 22-repository baseline including active remote-only repositories, native commands, current roadmap/tracker, deployment and dependency evidence. Benchmark current search/analyzers. Reconcile safe RepoWise indexes and report dirty-source limitations.
7. Use the bounded roadmap-based product and infrastructure proposals to select useful implementation batches within current product direction. Preserve product-specific demand, counsel and mobile-scope constraints.
8. Read authoritative Exchange state when accessible; prepare exact mailbox changes and rollback, preserving existing delivery transports. No permission/forwarding changes or sends.
9. Independent task and final reviews; assemble diffs, tests, findings, remaining blockers and rollback into external release records. Integrate validated batches and verify exact deployed revisions and affected workflows.

## Ownership and artifacts

AgentHub owns reusable implementation and curated guidance. Generated reports and task execution records live under `%LOCALAPPDATA%/AgentHub/portfolio-engineering/portfolio-improvement`. Operational mailbox evidence is kept separately there and never indexed or committed. Each product owns its fixes and native validation.

## Progress

- Foundation, retrieval, tenancy, notification, retirement and contact-relay fixes
  are prepared locally. Independent reviews and native verification are recorded
  in the external approval package; none establishes a production release.
- The 22-repository inventory includes Empowera and contact-email-relay. Product
  validation is bounded and separately reported; Empowera's stale dependency lock
  prevents a faithful frozen behavioral test run.
- Ten business-product proposals and eleven site/tool/infrastructure proposals
  are prepared for selection. SHTrial receives no feature proposal.
- Seven clean stale indexes were refreshed and three missing local indexes were
  initialized. The standard check now has seven remaining freshness failures,
  all on checkouts with uncommitted work. Index updates do not certify those diffs.
- Exchange changes remain blocked on authenticated administrative readback.
  The local exporter and target configuration are prepared; no mailbox mutation
  or mail send has occurred.
- Authoritative resumable execution ledger: `%LOCALAPPDATA%/AgentHub/portfolio-engineering/portfolio-improvement/progress.md`.
- Execution resumed with release authorization on 2026-09-09. All seven prepared candidates matched their recorded file hashes at restart; upstream and runtime checks must still precede each release. Release evidence belongs in the external ledger's `releases/` directory.

## Decisions

- Work in task branches in clean existing checkouts; create an approved `C:/wt` worktree when unrelated edits or simultaneous writers require it. This follows the user's narrower worktree policy and preserves installed environments.
- Keep generated review packages outside repositories, overriding skill-default `.superpowers` storage to comply with AgentHub's runtime-output boundary.
- Prepare Renovate in dry-run mode with an explicit allowlist, no schedule and no automatic merges. Existing Dependabot repositories remain on Dependabot.
- Preserve intentional version differences, retired SHTrial, local-only Empowera, and all mobile freezes.

## Validation and rollback

Run focused behavior tests before native broader verification. Required failure fixtures cover unavailable tools, stale evidence, identity/scope mismatches, tenancy, mail recovery, and each redirect rule. Each task report records actual commands/results. Record the prior deployment and source revision before release; rollback uses the repository's existing mechanism and preserves unrelated data. Keep committed, integrated, deployed and workflow-verified stages distinct.
