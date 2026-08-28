# Local-AI operating platform and fleet repair

## Purpose

Make `D:\Local-AI\registry.json` the executable runtime contract; add durable
jobs, reconciled GPU leases, deterministic routing, diagnostics, provenance,
retrieval evaluation, QA, gateway adapters, and deploy the AgentHub-owned
`local-ai` knowledge capability across every mapped host without adding a
redundant plugin.

## Boundaries

- `D:\Local-AI` remains non-Git and local-only.
- No optional router model, customer data, owner-voice corpus, Clerk account, or
  password change is in scope.
- Existing staged evidence and Product Demo Studio work must remain intact.
- AgentHub owns `local-ai` as `skills+cli`; no Codex plugin is created.

## Verified starting state

- AgentHub index recovery backup:
  `C:\Users\SaroshHussain\AppData\Local\AgentHub\recovery\agenthub-20260828-002352`.
- Four missing blobs restored byte-for-byte with `git hash-object --no-filters`;
  `git write-tree` succeeded and `git fsck --connectivity-only --no-reflogs`
  reported no connectivity errors.
- Local-AI pre-change release snapshot:
  `D:\Local-AI\data\artifacts\platform-releases\20260828-002650-pre-p01`.
- AgentHub baseline commit: `68bbc126a2a7a7185848ab8564946036742de5d7`.

## Progress

- [x] Recover Git objects and preserve the original index/staging intent.
- [x] Snapshot affected Local-AI control/config files and initial service state.
- [x] Extend registry schema to revision `2026-08-28.1` with runtime, routing,
  privacy, quality, resource, adapter, and fallback contracts.
- [x] Add SQLite jobs, materialized manifests, retry/resume/cancel, and leases.
- [x] Route legacy heavy commands through blocking durable jobs.
- [x] Add capability discovery, deterministic routing, read-only doctor, docs,
  knowledge, QA, and loopback gateway surfaces.
- [x] Add synthetic platform fixtures and focused contract tests.
- [x] Finish canonical references/validator and the Local-AI content hash.
- [x] Run Product Demo Studio focused contracts and the broad Local-AI suite;
  both exposed independent red gates, so full AgentHub/fleet validation stops.
- [x] Run the permitted synthetic live smoke; queued built-in voice and QA pass,
  while queued ASR correctly blocks on an external Cursor-owned GPU process.
- [x] Commit explicit AgentHub pathspecs and refresh RepoWise. Fleet apply remains
  prohibited by the red existing-work gates; report managed skill/MCP drift and
  unsupported hosts precisely.

## Decisions and discoveries

- `ai.ps1 start all` now means core services; transient ComfyUI/Invoke/media
  engines must be requested explicitly and are reconciled through GPU leases.
- Unknown GPU processes block work with a stable issue code; the platform does
  not kill or reclaim them.
- Generated docs record the registry revision and immutable AgentHub baseline
  provenance. Final commit and fleet deployment receipts are separate evidence,
  avoiding a self-referential tracked commit hash.
- Product-specific operator material remains in the product runbook; the shared
  Local-AI operator guide is now product-neutral.

## Validation evidence

- `validation/tests/test_platform.py`: 9 passed.
- `ai.ps1 capabilities --json`, `route --intent image --quality preview --json`,
  and `job list --json`: exit 0 with structured output.
- `ai.ps1 doctor --json`: 0 errors before generated-doc sync; stopped services
  were warnings, not errors.
- `ai.ps1 docs sync --json` and `docs check --json`: current for both runtime and
  AgentHub guide.
- Real queued GPU voice job `20260828T061507-d16d912a2bf2`: succeeded with
  built-in Aiden, synthetic text, seed 4242, and SHA-256-bound WAV artifact.
- `ai.ps1 qa` on that WAV: media decode, stream integrity, loudness, and local
  privacy checks passed; owner identity was correctly not applicable.
- Queued ASR jobs blocked with `GPU_OCCUPIED_UNKNOWN`. The occupant was traced to
  a separate Cursor task running the Rexa owner-voice batch; it was not killed.
- Broad Local-AI test run: 640 passed, 51 failed, 377 subtests passed. The new
  platform contract file itself remains 9/9 passing. Failures include older
  capture/finalizer fixture drift and existing health/media regressions.
- Product Demo Studio focused run: 238 assertions, 12 failures. The dominant
  failure is canonical-rubric path mismatch in preserved calibration fixtures;
  its staged work and registry hash were not modified.
- `Validate-AgentHub.ps1`: fails only on `contentHash drift: product-demo-studio`;
  Local-AI package validation and its updated hash pass.
- The AgentHub implementation commit contains only the intended Local-AI
  canonical package, validator, plan, and registry update.
- RepoWise single-repository status was refreshed and verified after commit.
  Fleet apply was not run because the Product Demo Studio and broad Local-AI
  gates are red.

## Remaining risks and rollback

- Live GPU generation can expose adapter or lease behavior not exercised by
  synthetic tests. Use only synthetic inputs and restore the recorded stopped
  state afterward.
- Existing Product Demo Studio work is adopted only if its focused contract
  tests pass. Otherwise stop fleet deployment without altering it.
- Roll back Local-AI with the hashed pre-change release snapshot, after checking
  live jobs and listener ownership. Roll back AgentHub with an explicit revert of
  the intended commit; never reset the shared worktree.
