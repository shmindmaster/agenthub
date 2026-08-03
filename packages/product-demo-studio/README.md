# product-demo-studio

Current package release: **1.7.0**. AgentHub is the canonical owner of the versioned product-video
workflow, schemas, generation/review roles, release policy, remediation routing, and deployment
metadata. Existing product-specific capture/render implementations are migration inputs; new
production work lives in the external AgentHub workspace and maps evidence into this shared
contract. The reviewed mapping is documented in
`skills/product-demo-studio/references/product-pipeline-compatibility.md`.
The complete self-contained persuasion, craft, production,
automation, and measurement standard is bundled at
`skills/product-demo-studio/references/killer-demo-production-guide.md`; the adjacent compact
playbook maps it to the package's normalized JSON validators.
The synchronized Visual Communication & Asset Generation Guide is bundled beside it and is owned
by `product-demo-studio-visual-assets`; it supersedes stale narration/model tables and forbids
generated product UI or fabricated results.
Version 1.2 adds a validated interactive product deep-dive derivative and an immutable private
review-delivery lane. Portfolio destinations remain AgentHub deployment configuration in
`registry/product-video-delivery.json`; they are not hard-coded into this repo-agnostic plugin.
Version 1.3 makes screen-space utilization and guided-screencast choreography mechanically
required: clean page/fullscreen capture, at least 50% planned active-region coverage, real
pointer/control/state transitions, visible click cues, and result-before-spoken-result timing.
Version 1.3.1 activates the same native plugin package in Cursor after owner reauthorization;
Cursor now receives the package's skills, agents, and MCP ownership instead of a loose-skills-only
fallback.
Version 1.4 makes professional screencast craft enforceable: decelerating cursor paths, click
settle/hold and interaction-specific feedback, one no-drift snap zoom per beat, 2× capture scale
with no crop upscaling, honest dead-time/text-entry treatment, annotation reading time, and a privacy-safe optional
DOM-interactive derivative strategy.
Version 1.5 makes those craft contracts fail closed in deterministic preflight, derives delivery
pixel density from real geometry, requires beat timing evidence, and adds canonical-rubric isolation,
symmetric pass/fail evidence, calibration, tightening-only vertical overlays, and capability-
detected GPU-first media work with checksum-bound acceleration provenance and deterministic CPU
fallback. Preflight reruns
the canonical craft validators against their checksum-bound inputs and rejects acceleration
selections that do not match functional probes. Reviewer calibration receipts bind both fixture input and derived
result-payload hashes, while remediation families use fingerprints derived from stable accepted-
finding category/routing identity instead of IDs, mutable review wording, or caller-selected labels.
Version 1.6.1 moves all work outside product repositories, adopts pinned Playwright plus Recast for lean capture and finishing, removes the vendored Remotion rules, and removes cryptographic signing, trust registries, the reviewer broker, intermediate
human approval gates. It keeps operational read-only execution receipts, makes acceptance and
refinement autonomous through the terminal independent verifier, and reuses the existing
`D:\Local-AI` CUDA runtime on demand without installing or starting another service. The first
human touchpoint is the final presentation. It also removes the last stale compatibility wording
that could be misread as an intermediate approval requirement.
Version 1.6.2 removes the legacy runtime probe. Media acceleration now resolves the
shared Local-AI registry from `AGENTHUB_LOCAL_AI_REGISTRY`, then `AGENTHUB_LOCAL_AI_ROOT`, with
`D:\Local-AI` as the Windows capability default.

A cross-agent plugin/skill suite for autonomously assessing demo-worthiness, reconciling, capturing,
composing, narrating, rendering, and QA'ing persuasive product demo / marketing videos with
pinned Microsoft Playwright CLI/core capture, an episode-appropriate external finisher,
provider-agnostic TTS, optional exceptional Remotion composition, and Descript — built to be invoked against
**any** repository, not a fixed portfolio. It treats the target repo as read-only input for video
production, keeps new production workspaces outside product source trees, and packages accepted
videos and evidence to the AgentHub-mapped OneDrive destination.

## Updating this canonical package

Any content change to this package requires a version bump — host installs are pinned by version
directory, so a canonical edit without a bump silently never propagates to an already-installed
host copy (see `tests/Validate-AgentEcosystem.ps1`'s `deployment-freshness:*` checks). Sequence:

1. Edit the canonical source under this directory.
2. Bump the version everywhere it is asserted: every `.claude-plugin/.codex-plugin/.cursor-plugin/
   .qoder-plugin/plugin.json`, `policy/host-parity.json` and
   `policy/product-video-policy.json` (`capabilityVersion`, not `schemaVersion`), this README's
   release line, `scripts/validate-package.mjs` and `scripts/validate-guide-sync.mjs`
   (`expectedVersion`), `scripts/validate-host-parity.mjs`, and
   `skills/product-demo-studio/references/product-pipeline-compatibility.md`.
3. Recompute and update the registry content hash:
   ```powershell
   cd C:\Repos\shmindmaster\agenthub
   . .\scripts\RegistryContentHash.ps1
   Get-AgentHubRegistryHashBasisValue -Path 'C:\Repos\shmindmaster\agenthub\packages\product-demo-studio'
   ```
   Paste the result into `registry/capabilities.json`'s `product-demo-studio.contentHash`.
4. Run the package validators from this directory: `node scripts/validate-package.mjs`,
   `node scripts/validate-host-parity.mjs`, `node scripts/validate-guide-sync.mjs`,
   and `node tests/run-contract-tests.mjs`.
5. Run the ecosystem validator from the repository root:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1`.
   Its `deployment-freshness:*` checks will now correctly report every already-installed host
   copy as stale until it is redeployed.
6. Re-deploy the updated package into each host that has a live install (reinstall/update the
   plugin in that host) — this is a separate step from the checks above, which only detect drift.

## Skills

| Skill | Purpose |
|---|---|
| `product-demo-studio` | Router. Enforces Product Experience handoff → episode/truth architecture → timed source → deterministic state/capture → narration/composition → evidence/preflight → four reviews/arbiter → remediation → mandatory final independent review and verification → video-or-feedback. Start here. |
| Official Remotion plugin | Optional exceptional composition fallback only when the default Recast pipeline cannot express a required visual; AgentHub does not vendor a copy. |
| `product-demo-studio-capture` | Deterministic browser-automation capture conventions: fixed viewports, reduced motion, discover-first auth, seeded data only, capture manifests, redaction rules. |
| `product-demo-studio-visual-assets` | Marketing/journey visual survey, non-product-UI asset generation, current model/voice verification, provenance, disclosure, and accessibility. |
| `product-demo-studio-narration` | Provider-agnostic TTS narration: generation, segment-level regeneration, timing, narration style. |
| `product-demo-studio-render` | Render orchestration, the video/scene catalog schema, the product-claim ledger, and the automated evidence gate that must pass before a render is accepted. |
| `product-demo-studio-qa` | Immutable evidence package, deterministic preflight, four independent schema-valid reviews, release arbitration, remediation/rerender, and mandatory final independent review and verification. |
| `product-demo-studio-descript` | Optional third-party editorial finishing. Any edit creates a new candidate and forces new evidence/review/final verification; publishing requires explicit task authority. |

## Agents

Portable prompts under `agents/` define the same permissions and outputs on plugin-aware and
skill-only hosts:

- generation: Episode Architect, Script and Storyboard Generator, Capture and Product-State
  Generator, Narration and Audio Generator, Composition and Render Generator, and Automated
  Preflight;
- independent review: Story and Experience; Screen, Accuracy, and Compliance; Audio, Captions, and
  Synchronization; Technical and Frame Integrity;
- decision/control: Release Arbiter, least-privilege Remediation Agent, and the mandatory terminal
  independent reviewer/verifier (`final-verifier`).

Plugin-aware hosts may invoke them as `product-demo-studio:<name>`. Skill-only hosts resolve the
same prompts from the canonical package and create equivalent isolated contexts. The old five-role
review split is replaced: product truth and visual accuracy now belong to Screen/Accuracy/
Compliance, while visual storytelling belongs to Story/Experience. No review criterion was
dropped.

`policy/host-parity.json` binds every registered host to the same contracts. Capability exposure
alone is not release eligibility: a live reviewer, arbiter, or final-verifier run must record
host-native read-only enforcement. Prompt-only or broad-write contexts return
`PIPELINE_BLOCKED`. Running `validate-host-parity.mjs` without arguments is deliberately a static
source-inventory check and makes no live deployment or runtime-parity claim. A live claim requires
`--live-deployment-report <path>` with exact canonical contract hashes plus per-host deployment,
native-isolation, and smoke-test evidence.

Each isolated role records one small execution receipt containing the role, context, candidate,
host-native read-only mechanism, tool classes, and timestamps. It is an operational trace, not a
security attestation; enforcement comes from launching the host's native restricted role/context.
No signing service, key registry, broker, or resident process is required. A host without that
restricted context routes the candidate to `PIPELINE_BLOCKED`.

## Contracts and release policy

`schemas/` contains the strict, host-independent evidence-package, preflight, finding, review,
remediation, and release-decision contracts. Review reports are accepted only after local
validation. Release decisions are limited to `PASS`, `REMEDIATE`, `PRODUCT_BLOCKED`, and
`PIPELINE_BLOCKED`.

`PASS` requires zero blocker/critical findings; Story and Experience >= 85; Audio/Captions/
Synchronization >= 95; and complete passes for accuracy, compliance, privacy, technical
integrity, browser playback, claims, checksums, provenance, captions, synchronization, and visual
integrity. After arbiter `PASS`, the mandatory terminal independent reviewer/verifier must return a
schema-valid `PASS` for the exact unchanged candidate before packaging, delivery, or release.
Acceptance is automated. The pipeline iterates through remediation and fresh candidates until the
arbiter and terminal independent verifier both return schema-valid `PASS`, or it produces an
evidence-backed product/pipeline blocker. The first human touchpoint is presentation of that final
candidate or blocker report. Public publishing is a separate consequential action outside this
automated acceptance contract.

## Scripts

All scripts are plain Node (`.mjs`, no build step, zero npm dependencies) under `scripts/`, always
invoked from the plugin with the target repo as product input — never copied into one:

- `video-cli.mjs` — single verb-based entry point for the whole pipeline (`inventory discover
  readiness storyboard claims reset capture voice render-proxy frames preflight review validate-
  review arbitrate validate-decision validate-assignment qa revise render-candidate package-review
  package all`).
- `package-review.mjs` / `validate-review-delivery.mjs` — resolve an AgentHub-owned
  product-to-OneDrive mapping, require arbiter and mandatory final-verifier `PASS`, and create a
  non-overwriting `Review/<candidateId>` package marked `review-only` for final presentation.
- `validate-interactive-deep-dive.mjs` — validates role routing, deep-linkable operational scenes,
  interactive proof/evidence, adjacent trust controls, contextual CTAs, instrumentation,
  accessibility fallbacks, and synthetic sandbox safety without requiring fabricated metrics or
  private chain-of-thought.
- `validate-demo-readiness.mjs` / `validate-storyboard.mjs` — fail-closed normalized contracts for
   video-vs-feedback classification and persuasion craft (cold open, before-state, one hero moment,
   all eleven worthiness criteria, three-rung WIIFM with compatible refined aliases, emotional
   target, annotation limits, cadence, end card, explicit interaction choreography, and delivery
   framing).
- `repo-registry.mjs` — reports whether a target repo (`--repo <path>`, the default/primary mode)
  or a workspace of sibling repos (`--root <path>`, optional convenience) already has video
  infrastructure, and its actual shape.
- `scaffold-video-workspace.mjs` — idempotently creates a minimal pinned Playwright CLI/core capture workspace under the external AgentHub local work root (or an explicit external `--workspace`) and refuses paths inside the target repo. It does not add a compositor before the episode proves one is needed.
- `new-video-catalog-entry.mjs` — legacy migration helper; refuses repo catalog writes unless the caller supplies `--allow-legacy-repo-write` after explicit authorization.
- `render-videos.mjs` — renders one or all compositions from an external workspace or a retained legacy repo workspace during migration.
- `generate-narration.mjs` — provider-agnostic TTS (ElevenLabs / OpenAI, auto-detected from
  environment API keys), with per-segment regenerate-only-changed and checksummed sidecars.
- `compute-overlay-placement.mjs` — resolves a safe on-screen-text region from capture-manifest
  geometry (focus rect, protected regions, cursor path), so headlines/callouts never occlude the
  product.
- `technical-checks.mjs` — FFmpeg/ffprobe-backed technical QA against a versioned delivery spec:
  codec/profile/resolution/fps/color/audio/fast-start, decode/corruption, exact duplicate,
  black/freeze/loudness/clipping/silence, scene frames, contact sheet, and deterministic report
  generation with tool/command/input provenance.
- `validate-craft-contracts.mjs` / `preflight.mjs` — checksum-bound storyboard/capture validation,
  complete episode/segment coverage, ffprobe-measured raw-capture geometry, fail-closed evidence-
  package timing/provenance, canonical validator reruns, and
  deterministic-report gates before review.
- `validate-reviewer-calibration.mjs` — derives known-bad and clean-pass calibration outcomes from
  criterion-level reviewer outputs and evidence, then verifies execution receipts that bind
  the exact fixture-input and derived result-payload hashes.
- `detect-media-acceleration.mjs` — functionally probes NVENC and a local CUDA inference runtime,
  selects compatible GPU-first media paths, and emits checksumable fallback provenance; preflight
  rejects any selected encoder/device that did not pass those probes. Local inference discovery
  uses the shared Local-AI capability through `AGENTHUB_LOCAL_AI_REGISTRY` or
  `AGENTHUB_LOCAL_AI_ROOT`; the Windows default is `D:\Local-AI`.
- `validate-review-report.mjs`, `validate-release-decision.mjs`, and
  `validate-remediation-assignment.mjs` — zero-dependency validation of the shared machine-readable
  contracts.
- `validate-claims.mjs` / `validate-capture-manifest.mjs` — hand-rolled schema validators for the
  product-claim ledger and capture manifests, including screen-space utilization,
  cursor/action/click choreography, and narration synchronization.
- `check-evidence-gate.mjs` — validates the exact candidate, PASS arbiter decision, and PASS final
  verification hashes before a render can be treated as accepted.

## Design notes

- No `commands/` or `hooks/` — this plugin ships skills, portable agent prompts, strict schemas,
  zero-dependency validators, and scripts.
- Fully self-contained and repo-agnostic: the only required input to repo-operating scripts is `--repo <path>`
  (or a manifest path). No script assumes a specific multi-repo workspace, portfolio registry, or
  identity provider; `repo-registry.mjs --root` is an optional convenience only.
- Generic Remotion APIs and framework mechanics are owned by the current official
  `remotion:remotion-best-practices` plugin. AgentHub does not copy or fork its rule library.
- `.mcp.json` optionally bundles Descript's remote MCP server
  (`https://api.descript.com/v2/mcp`) so enabling this plugin offers a one-time OAuth connection
  to your own Descript Drive, without requiring the separate claude.ai connector setup. If a
  Descript connector is already connected at the session level, use those tools instead — don't
  connect twice. Any edit invalidates the previous candidate; MCP-only output without locally
  checksumable bytes is `PIPELINE_BLOCKED`, and publishing requires explicit authorization.
  ElevenLabs narration is delegated to the canonical `elevenlabs` capability; Product
  Demo Studio does not duplicate that provider API. OpenAI narration remains a local
  provider adapter. Supply provider credentials only through environment-variable references.
- This plugin does not scaffold video infrastructure into product repos. New workspaces and
  generated evidence stay in the external AgentHub work root; accepted review packages go to the
  OneDrive destination in `registry/product-video-delivery.json`.
- Fleet-distributed skill-only hosts resolve this directory from the `product-demo-studio`
  capability's `canonicalSource` in the Agent Capabilities registry. They do not rely on the
  Claude-only `CLAUDE_PLUGIN_ROOT` environment variable or duplicate the scripts into product repos.
