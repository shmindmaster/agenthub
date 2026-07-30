# Portfolio automation-gate inventory

Audit scope: the twelve repositories named in the portfolio, their connected Linear work, and the project pages returned by Notion search. The audit distinguishes a reusable machine control from an accountable external action. A proxy, test, or synthetic fixture can support a decision; it cannot impersonate a customer, clinician, counsel, signatory, payer, or regulator.

## Decision rule

| Class | Default | Required proof |
| --- | --- | --- |
| Machine | Auto-proceed | versioned source, deterministic test or invariant, reproducible receipt |
| Automated evidence | Go / pivot / stop | provenance, predeclared threshold, freshness, falsification |
| Accountable external action | Draft only | authority scope, identity/contract record, immutable receipt |
| Fail-closed exception | Halt and queue | reason code, supporting evidence, bounded resolution |

No interview, workshop, or discretionary review count is a release prerequisite.

## Repository inventory

| Repository | Remove or systematize | Retain as an accountable boundary |
| --- | --- | --- |
| WarrantyGains | Public policy/source freshness, demand/pricing signals, preflight consistency, evidence completeness | Dealer engagement, OEM portal submission, legal/compliance conclusion |
| ABACare | AI regression/evaluation, policy monitoring, minimum-necessary validation, canary analysis | Lawful real-PHI authority, binding parent/payer action, clinical decision |
| AgentHub | Registry/ownership validation, config drift checks, local contract checks | Provider activation, OAuth/credential creation, cross-boundary operations |
| CoLedger | Public-signal research, synthetic benchmark, close/reconciliation invariants | Data-sharing authority, paid-pilot agreement, financial attestation |
| CrewScore | CI-only landing, auto-release, corpus validation, product-signal collection, distribution drafts | Publisher binding, exploit triage, optional third-party account creation |
| GentleNext | Public demand synthesis, synthetic benchmark, provenance, release checks | Data/pilot agreement, real-PHI authority, live care-delivery action |
| Lawli | Citation/deadline QA, provenance evaluation, source freshness, read-only contracts | Case-specific legal strategy, filing/representation, confidential-matter authority |
| LexAlign | Matter-isolation tests, claim benchmark, read-only API/MCP contract tests | Legal judgment, matter-scoped authority, partner contract |
| RepoContext | Index integrity, sensitive-path denials, retrieval contract/freshness checks | Production endpoint authorization, credentials, source-access authorization |
| Sabhi | Intake classification, drafts, policy provenance, transaction invariants | Payments, inventory/delivery promises, outbound commitments |
| SubOps | Ingestion, reconciliation, extraction/math evaluation, evidence packets | Carrier dispute submission, real-data authority, financial statement of record |
| Verigence | Market signals, synthetic cases, AI evaluation, policy monitoring, canary analysis | Real-PHI authority, consent, provider/payer transaction, external commitment |

## PMF and research backlog changes

| Linear issue | Disposition |
| --- | --- |
| SH-2414 | Existing canonical automated demand-validation system; public signal monitoring, instrumentation, and quantitative go/pivot/stop logic |
| SH-2124 | Already revised to replace manual panel/interviews with synthetic/de-identified benchmark and reproducible evaluation |
| SH-2088 | Canceled as a duplicate manual interview/observation gate; superseded by SH-2414 and SH-2124 |
| SH-2092, SH-2093 | Rewritten as WarrantyGains automated demand/policy and pricing/buying-path evidence work |
| SH-2115 | Rewritten as CoLedger automated decision, benchmark, and partner-readiness evidence |
| SH-2107 | Rewritten as GentleNext automated demand and synthetic benchmark work |
| SH-919 | Was already canceled; its retained description now records the automated replacement rather than an interview requirement |
| SH-2142 | Rewritten as LexAlign public-market and adversarial contract validation |
| SH-1539 | Rewritten as automated pricing, packaging, and unit-economics research |

## Controls that become the release and product gates

1. Versioned primary-source ledger: locator, retrieval time, effective date, hash, classification, and freshness state.
2. Locked evaluation harness: fixtures/corpus, model and prompt version, deterministic checks, metrics, counterfactual/source-removal tests, and failure artifacts.
3. Explicit go/pivot/stop thresholds: reviewed at configuration time, then decided by the receipt rather than an open-ended meeting.
4. Progressive delivery: feature flag, small canary, SLO comparison to control, automatic rollback, immutable deployment receipt.
5. Contract and invariant testing: schema compatibility, tenancy/authorization, idempotency, provenance, evidence completeness, and no-write boundaries.
6. Fail-closed exception path: stale, ambiguous, conflicting, unsupported, or out-of-scope inputs never silently proceed.

## Non-substitutable residuals

Automation must not infer authority or take an irreversible action merely because a proxy signal is positive. The remaining boundaries are narrowly limited to contracts/signatures, lawful real-data or PHI authorization, legal/clinical judgment, payments, regulatory/OEM/carrier submissions, public binding communications, and production access/credential creation. Automation prepares bounded drafts, evidence, and audit receipts for those boundaries.

## Validation

The canonical machine-readable policy is `registry/automation-gates.json`. Run:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\scripts\Test-AutomationGatePolicy.ps1
Invoke-Pester -Path .\tests\AutomationGatePolicy.Tests.ps1
```
