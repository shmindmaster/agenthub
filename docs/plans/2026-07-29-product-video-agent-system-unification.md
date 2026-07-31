# Product-video agent-system unification

> Superseded contract note (2026-07-31): Product Demo Studio 1.5.2 replaced the signing design,
> fixed retry cap, and intermediate human checkpoints below with host-native role isolation, plain
> operational receipts, automated acceptance, continuous remediation, and final-presentation-only
> human involvement. The current package policy and validators are authoritative.

Date: 2026-07-29
Classification: personal capability work
Canonical owner: `handoff/product-demo-studio`
Implementation worktree: `C:\wt\agenthub\product-video-unification`
Removal gate: remove the worktree only after the reviewed commit is integrated into `main`, deployed, and the live fleet parity check passes.

## Decision

AgentHub's existing Product Demo Studio remains the only shared product-video capability. Product-specific capture and rendering pipelines remain in their owning repositories because they contain product contracts, synthetic fixtures, authentication boundaries, and release semantics that must not be centralized.

This change standardizes the contract between those local pipelines and the shared capability. It does not introduce a shared video runtime, copy product media into AgentHub, or make a product repository depend on AgentHub at runtime.

Product Experience Engineering remains the upstream owner of the pre-video product-readiness handoff. Browser Toolkit owns browser execution mechanics. `use-elevenlabs` owns ElevenLabs provider mechanics. Product Demo Studio owns product-video policy, workflow, evidence, review, remediation routing, release arbitration, and deployment parity.

## Inventory and disposition

| Implementation | Actual role | Disposition |
|---|---|---|
| AgentHub Product Demo Studio | Repository-agnostic readiness, story, capture, narration, composition, render, QA, and evidence policy | Retain and upgrade as canonical |
| AgentHub Product Experience Engineering | Pre-video product-readiness assessment and remediation handoff | Retain as prerequisite |
| AgentHub Browser Toolkit | Browser and Playwright execution mechanics | Retain as separate execution owner |
| AgentHub `use-elevenlabs` | Account, API, STT, and TTS provider mechanics | Retain as separate provider owner |
| ABACare `studio` | Product-bound capture, TTS, Remotion, captions, ASR, ledgers, release tests | Retain product-local; map artifacts to canonical contracts |
| Verigence `packages/videos` | Product-bound Playwright/Remotion/TTS pipeline and doctor/release gates | Retain product-local; map artifacts to canonical contracts |
| SubOps video capture and QA scripts | Product-bound Playwright capture, FFmpeg rendering, claims/redaction gate | Retain product-local; support repository-native adapter |
| CrewScore release demo | Fixture-driven product demo, local narration, truth/claim evidence | Retain product-local; support repository-native adapter |
| WarrantyGains `apps/videos` | Product-bound Remotion composition and render scripts | Retain product-local; support repository-native adapter |
| Legacy Grok SubOps studio worktree | Historical implementation removed from current SubOps | Preserve pending separate worktree-ownership review; never treat as canonical |
| Deployed Product Demo Studio skills/plugins | Host-native consumers of AgentHub canonical source | Regenerate from AgentHub and verify exact parity |
| Notion `prompt.produce-demo-video.v4` | Historical prompt that rejects ledgers and review gates | Supersede after the AgentHub replacement is deployed |
| Linear video issues | Product-specific requirements, defects, and historical decisions | Reconcile as evidence; do not use as personal capability control plane |

## Canonical contract

The package version introduces:

1. One strict finding schema shared by every reviewer and host.
2. Four independent read-only reviewers:
   - Story and Experience
   - Screen, Accuracy, and Compliance
   - Audio, Captions, and Synchronization
   - Technical and Frame Integrity
3. A deterministic preflight contract that must pass before review.
4. A read-only Release Arbiter that validates, deduplicates, resolves, scores, routes, and decides.
5. A least-privilege remediation-assignment contract.
6. A fresh read-only final-verifier contract.
7. Host-native isolated role execution recorded in a plain operational receipt; the receipt is not
   a security attestation and requires no key, registry, broker, or resident service.
8. Automated acceptance bound to the exact candidate, arbiter decision, and final-verification bytes.
9. Product-pipeline compatibility mappings without shared product code or data.
10. Versioned manifests, local validation, deployment regeneration, and live parity checks.

The four-reviewer model replaces the old five-reviewer model. Product-truth and visual accuracy are merged into Screen, Accuracy, and Compliance. Visual storytelling and direction move into Story and Experience. Audio and technical responsibilities expand to captions/synchronization and frame-integrity requirements respectively. No unique review criterion is dropped.

## Release policy

Machine arbitration may return only `PASS`, `REMEDIATE`, `PRODUCT_BLOCKED`, or `PIPELINE_BLOCKED`.

`PASS` requires:

- zero blocker or critical findings;
- Story and Experience score at least 85;
- Audio, Captions, and Synchronization score at least 95;
- complete passes for accuracy, compliance, privacy, technical integrity, browser playback, claims,
  checksums, provenance, captions, synchronization, and visual integrity;
- valid evidence and reproduction commands for the immutable candidate.

The pipeline continues autonomously through validation, independent review, remediation, rerender,
arbitration, and terminal verification until `PASS` or an evidence-backed blocker. The first human
touchpoint is the final presentation. Public publishing remains a separate consequential action.

## Validation and deployment

- All examples use synthetic data and local fixtures.
- Product repositories are inspected read-only; no product data or media is copied.
- Validation is repository-native and local. No hosted GitHub Actions workflow is added or run.
- Cursor surfaces remain retained-disabled and are not invoked.
- The active GitHub account for AgentHub operations is `shmindmaster`.
- Changes are reviewed before a direct, non-editor commit to `main`, matching the owner's explicit delivery policy.
- Deployment must regenerate host-native packages from AgentHub, preserve optional Descript exposure without duplicating a session-level connector, and prove content/version parity across supported live hosts.
- Capability exposure is not reviewer eligibility. A reviewer, arbiter, or final-verifier run
  without host-native read-only enforcement is `PIPELINE_BLOCKED`; prompt text cannot substitute
  for an enforcement boundary.
- The host must provide its native restricted role/context. Each role records a plain operational
  receipt; missing or writable contexts fail closed, and no signing infrastructure is required.
