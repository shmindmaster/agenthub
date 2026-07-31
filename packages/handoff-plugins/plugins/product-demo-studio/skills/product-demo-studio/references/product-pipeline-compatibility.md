# Product-pipeline compatibility

Version: 1.5.0
Owner: AgentHub `handoff/product-demo-studio`

This matrix maps known repository-native product-video pipelines to the canonical Product Demo
Studio contract. It is a compatibility layer, not permission to copy product code, media, data,
authentication state, or credentials into AgentHub.

Always run `repo-registry.mjs --repo <path>`, read the repository's instructions and video README,
and inspect current files. These are observed shapes, not permanent assumptions.

| Pipeline shape | Preserve locally | Canonical contract mapping |
|---|---|---|
| ABACare `studio` | Authenticated Playwright capture, TTS, Remotion composition/mux, captions, ASR, narrative/claim guards, release ledger, delivery scripts, and unit tests | Capture manifest and browser reports -> evidence package; narration/ASR/captions -> audio evidence; claim/release ledgers -> truth/claim/provenance; Studio tests -> preflight validations |
| Verigence `packages/videos` | Playwright/Remotion, provider fallback, cache/concurrency controls, doctor CLI, release gates, and no-production-leak tests | Doctor/release reports -> preflight; capture/render manifests -> evidence/provenance; TTS/cache manifests -> narration checksums; leak tests -> privacy/compliance evidence |
| Sabhi `studio` | Product catalog, capture, narration, composition, mux, QA, and delivery, including current product-specific CI | TODO capture references fail artifact completeness; loudness evidence must meet the declared target; local manifests map to canonical evidence without importing studio code |
| Lawli `apps/videos` | Deployed-flow capture, narration, mux, QA, and delivery | Deployed browser reports -> playback/capture evidence; narration/caption/QA outputs -> audio evidence; keep the product package and its commands local |
| SubOps Playwright + FFmpeg | Repository-owned video-capture tests, FFmpeg render scripts, artifact/claim/caption/redaction checks, guarded seed path, explicit publication attestation | Capture assertions/browser evidence -> evidence package; FFmpeg report -> technical evidence; claims/captions/redaction -> accuracy/privacy; attestation remains separate human publication gate |
| CrewScore release demo | Fixture-driven local app, Playwright capture, Windows narration, render scripts, truth sheet, claim ledger, and human-review template | Fixtures/state -> synthetic provenance; truth/claim files -> canonical evidence; narration/render outputs -> audio/technical reports; review template -> external human attestation |
| WarrantyGains `apps/videos` | Remotion compositions, render groups, catalogs, and production manifests | Catalog/story source -> episode/storyboard; composition/render manifests -> source/render provenance; masters/variants -> media artifacts; add missing capture/review evidence without replacing the local app |
| LexAlign `apps/videos` | Documented four-video workflow with an empty current catalog | Treat as retained partial infrastructure; no episode may proceed until the product-local catalog and current evidence are complete |
| Dormant `*_Video_Program` scaffold | Empty or incomplete Remotion/catalog setup with no release evidence | Inventory only. Do not report support or create media until readiness identifies a truthful episode and the missing evidence path is implemented |
| Generic `apps/videos` or `packages/videos` | Repository-specific catalog, composition, capture, render, and test conventions | Extend the existing convention; emit or adapt only the canonical evidence-package and decision contracts |
| Playwright + FFmpeg without Remotion | Deterministic browser capture and repository-native assembly | Remotion is optional. Meet the same evidence, review, release, and reproducibility gates with native tooling |
| No video infrastructure | Repository-native minimal workspace only when an approved episode is demo-worthy | Use the scaffold only after discovery/readiness; never create a second generic runtime in the product repo |

## Required adapter behavior

A product-local adapter may transform local manifest field names into the canonical JSON contracts.
It must:

- be stateless and repository-local;
- read source artifacts without moving or duplicating them;
- preserve original checksums and record the transformation version;
- fail on unknown required fields, stale candidate IDs, missing evidence, or unverifiable paths;
- never auto-attest privacy, compliance, synthetic-data confirmation, human watch-through, or
  external publication approval;
- never make the product build depend on AgentHub at runtime.

The canonical schemas are the cross-host contract. Product repositories remain the authority for
their product behavior, fixtures, build, capture, composition, and release-specific constraints.
