# Product-video system inventory

Snapshot date: 2026-07-29
GitHub account: `shmindmaster`
Notion coverage: connected `Apps Portfolio` workspace only
Linear coverage: connected `shorg` workspace
Mutation state: inventory was read-only

## Consolidation verdict

AgentHub `handoff/product-demo-studio` is the single shared capability owner. No product repository
imports it as a runtime dependency. Product repositories intentionally retain repository-native
capture/render pipelines; consolidation standardizes their evidence, review, remediation, and
release contracts rather than copying product code or media into AgentHub.

Product Experience Engineering remains the product-readiness prerequisite. Browser Toolkit and
repository Playwright own browser mechanics. `use-elevenlabs` owns provider mechanics. Descript is
an optional final-stage connector and must not be connected twice for one host/session.

## Active product-local implementations

| Product | Observed implementation | Disposition |
|---|---|---|
| ABACare | Full `studio`: authenticated capture, TTS, Remotion/mux, captions, ASR, narrative/claim guards, release ledger, delivery, tests, and CI | Retain product-local. Current SH-2318 directs a public surface of at most `capture`, optional `render`, and `deliver`; map internal evidence to AgentHub 1.0 without adding lifecycle coupling |
| Sabhi | Full `studio` with capture, narration, composition/mux, QA/delivery, and CI | Retain product-local. `TODO-CAPTURE` catalog assets and reported ~-21 LUFS against -16 LUFS are unresolved product-level evidence failures |
| CrewScore | Lightweight fixture-driven `demo/release-demo` with capture/render/narration, truth sheet, claim ledger, and human review | Retain product-local and map existing evidence |
| Lawli | Active deployed-flow capture/narration/mux/QA/delivery under `apps/videos` | Retain product-local and map existing evidence |
| Verigence | Active `packages/videos` Playwright/Remotion/TTS pipeline, doctor, no-production-leak tests, and release gates | Retain product-local and map existing evidence |

## Partial or dormant implementations

| Product | State | Disposition |
|---|---|---|
| LexAlign | Documented four-video process; current `apps/videos/src/content.ts` catalog is empty | Preserve partial infrastructure; do not claim production readiness |
| WarrantyGains | Four episode manifests; current `apps/videos/src/content.ts` catalog is empty | Preserve partial infrastructure; do not claim production readiness |
| SubOps | Current main retains capture/readiness plus Playwright/FFmpeg QA; former full `studio` was removed | Preserve current pipeline; historical Grok worktree remains noncanonical pending separate ownership cleanup |
| Empowera | Empty/incomplete Video Program scaffold with no release evidence | Treat as dormant, not a supported implementation |
| DocuMed | Empty/incomplete Video Program scaffold with no release evidence | Treat as dormant, not a supported implementation |
| Repocontext | Demo-readiness handoff only | Not a video-production implementation |

## Removed and superseded systems

- CoLedger's video system was added in PR 118 and removed by commit
  `ef27d210fa3a4094d0971cabeb102c8e52c82f40`.
- GentleNext's video system was added in PR 55 and removed by commit
  `3660df098140560fed8c2290324e66c8beba71da`.
- SubOps's former studio was added in PR 137 and removed from current main by commit
  `3b227fdc2893b8073656271a506a87ccff89cbea`.
- AgentHub branch `copilot/unify-standardize-product-video-system` is zero commits ahead and nine
  commits behind current `main`; it contains no unique implementation and is superseded.

Removed product systems are historical evidence, not deployment sources. Do not resurrect their
code or leave backlog paths pointing to deleted `studio/**` trees.

## Requirements and tracker drift

- Linear SH-2318 is the current ABACare simplification direction. It limits the product-local
  public command surface while preserving truthful capture/delivery gates.
- SH-2408 tracks a certified N7 episode missing from the ABACare capture catalog, an orphaned
  target, and long videos without readiness evidence.
- SH-2392's issue body says capture is blocked; newer comments say the tenant was reseeded and
  capture preflight passes. The issue body is stale.
- ABACare still records `POST_OVERHAUL_MEDIA_RELEASED=false`; readiness is not publication.
- SH-2057 remains open for a CoLedger implementation that was removed.
- SH-1899/SH-2064 still reference deleted SubOps `studio/**` paths.
- SH-2061 correctly makes Verigence production demand-gated after older specs were removed.
- SubOps GitHub issue 102 tracks unsupported pricing/statistics/latency claims relevant to any
  release claim ledger.

No Linear mutation was made during personal capability consolidation. These are product-level
issues and must be deduplicated/updated only during an authorized product task or by a release
arbiter reviewing an actual product candidate.

## Notion drift

- Prompt Library page `prompt.produce-demo-video.v4` / “Produce Demo Video” version 5.0.0 rejects
  claim ledgers, approval gates, and separate review ceremonies. That contradicts the user's
  current explicit AgentHub 1.0 release contract.
- “Portfolio QA Evidence Standard” still requires a reviewed release-evidence manifest and human
  approval.
- The Verigence operating-model mirror still describes older SH-1707–1713 tooling while current
  SH-2061 is demand-gated.

The Produce Demo Video prompt is superseded by the current AgentHub Product Demo Studio workflow.
The replacement describes automatic preflight, independent review, remediation, arbitration, and
terminal verification as one orchestrated capability with no intermediate human approval record.
The first human touchpoint is final presentation.

## CI, deployment, and release evidence

- Explicit product-video CI was found only in ABACare and Sabhi.
- No inspected GitHub Release across the fourteen repository snapshot contained product-video
  assets. Local delivery evidence is not GitHub publication evidence.
- Capture against a deployed product was observed in ABACare, Lawli, SubOps, and Verigence; this
  does not prove video publication or production approval.
- AgentHub validation is configuration validation, not a build/release pipeline. Product Demo
  Studio contract/version checks run through the local repository-native validators.
- AgentHub defines no GitHub Actions workflows. The retired DigitalOcean runner is not part of the
  validation path.

## Canonical migration

- Product Demo Studio manifests are versioned `1.5.3`; its full package tree is the registry hash
  basis.
- Thirteen canonical prompts replace the overlapping five-reviewer split with five generation/
  preflight roles, four isolated reviewers, an arbiter, remediation, and a fresh final verifier.
- Evidence, delivery-spec, deterministic-report, preflight, finding, review, remediation,
  decision, final-verification, execution-receipt, and release-evidence schemas are
  fail-closed and versioned.
- Real FFmpeg media tests prove codec/resolution/fps/color/audio/fast-start/decode/duplicate/frame/
  loudness checks and checksum-bound deterministic output; forged paths, policy drift, malformed
  reviews, stale bytes, and publication tampering are negative-tested.
- Remotion guidance is pinned to `remotion:remotion-best-practices` 1.0.5 by normalized tree hash.
  The only provider override routes voice generation to `use-elevenlabs`.
- `use-elevenlabs` is versioned `0.2.0` across all manifests, owns the TTS request surface, and is
  validated as a full-tree registry capability.
- Descript remains optional. Any edit creates a new candidate; unchecksumable output is
  `PIPELINE_BLOCKED`; publish requires explicit authorization for the exact currently approved
  bytes.
- Eighteen registered host mappings reference one source contract. This is static inventory, not
  proof of deployment or runtime parity. An orchestration-capable host may attempt review only
  when a live smoke report proves the deployed contract hash and the host records a read-only
  execution receipt. Every unverified, broad-write, or prompt-only context fails
  closed.

## Snapshot revisions

- AgentHub `66202dcd077b9631e5d521bc04ea96f93731c719`
- ABACare `631ed69e50d1cce7e0ba5656835ed28aa0e19bb8`
- CrewScore `1b219e2b479ab43219c354abe47f00b2703725cd`
- CoLedger `1bbadbda1d0d1df8882f8512a0e7461d6dacf4b8`
- GentleNext `589725451a7e95a18343064d52471ab61c0f9836`
- LexAlign `8cc1f0a5e49c54c71eb14f37a2df8994abf29b18`
- WarrantyGains `9296ad7e5edece3b9f2ebe8a86afb83725b1b7ce`
- Verigence `2dfdba35cc569e6571280c74a761a15d90339228`
- Lawli `e6dbb8c80965eb7d966dd2e3b88fceb79efc9d69`
- SubOps `d3d2d60ebc394d5e6dbf9ac65c0ca23f2db714ab`
- Sabhi `4e93e23d5a23ff8c5584e8d14ca1029e574f8444`
- Empowera `6792e61cde94a2aedf08612a28f0fb99356f463a`
- DocuMed `27fadb44a79e23cfa3d7a091e9806f0b91f2b241`
- Repocontext `86235a5860bcd4ddd94749ffc3a7ec2d112c7835`

Absence from an unconnected Notion workspace is not proven. Private owner-wide GitHub code search
did not provide reliable coverage; inventory evidence came from each repository's tree, files,
branches, issues, pull requests, workflows, releases, and commit history.
