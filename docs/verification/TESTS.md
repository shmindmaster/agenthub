# Tests

Commit `5002737`. Six focused registry and discipline tests ran in this pass (see the execution log); five passed and one found a real regression, which this change fixes. The aggregate runner and `Validate-AgentHub.ps1` did not run (the machine was at 0.4-0.6 GB free RAM). Inventory rows below say "not run in this pass" unless the log lists them.

## Inventory

Counts are from `git ls-files` at `5002737`.

| Suite | Count | How to run | Discovered by `Run-AllTests.ps1` | Status |
|---|---|---|---|---|
| Behaviour tests `tests/Test-*.ps1` | 75 files | `pwsh -NoProfile -File .\tests\Run-AllTests.ps1` (or one file directly) | yes (`:32-36`) | not run in this pass |
| Package validators `validate-plugin.ps1` | 2 (`packages/elevenlabs/tests/`, `packages/product-experience-engineering/tests/`) | via the runner | yes (`:37-41`) | not run in this pass |
| Node tests `*.test.mjs` | 7: `media-studio/tests/` x4, `security/scripts/` x2, `slack/mcp/contract.test.mjs` | `node --test <file>` via the runner | yes (`:42-46`) | not run in this pass |
| Registry validation `scripts/Validate-AgentHub.ps1` | 1 script | `pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1` | no (it is a check, run separately; many tests call it) | not run in this pass |
| Fleet standard `scripts/Check-RepoStandard.ps1 -All` | 1 script | as listed | no | not run in this pass |
| Python tests | 5: `elevenlabs/scripts/test_*.py` x2, `media-studio/scripts/test_content_*.py` x2, `repowise/tests/test_repowise_bridge.py` | called from `elevenlabs/tests/validate-plugin.ps1` (4) and `tests/Test-RepoWiseBridge.ps1` (1) | indirectly | not run in this pass |
| Execution-controls kit: Python `test_kit.py`, TS `kit.test.ts`, `schema.test.ts` | 3 files | `packages/product-experience-engineering/tests/validate-kits.ps1` (Python via `unittest discover`; strict `tsc` only if `EXECUTION_CONTROLS_TSC` is set, otherwise printed as SKIP, `validate-kits.ps1:31-40`) | **no**, see gap below | not run in this pass |
| Other package scripts `Test-*.ps1` under `packages/` | 4 (`Test-SpeechIntegrity`, `Test-MobileLab`, `Test-MobileLabAppConfig`, `Test-MobileLabIdle`) | called by tests in `tests/` | indirectly | not run in this pass |

Runner behaviour worth knowing: it parses `RESULT: N passed, M failed` from each PowerShell test and runs Node files with `node --test` (`Run-AllTests.ps1:68-80`); it exits 1 when it discovers zero files (`:49-52`). Whether that guard can actually fire was not tested (a check that has never been seen to fail is not yet evidence).

Gap: `packages/product-experience-engineering/tests/run-all.ps1:4-6` runs `validate-runtime.ps1`, `validate-demo-readiness.ps1` and `validate-kits.ps1`, but the aggregate runner only picks `validate-plugin.ps1`, and `validate-plugin.ps1` does not call them. Those three validators and the kit tests are not part of the aggregate suite.

## Categories the fleet directive asks for

| Category | Present in repo | Notes |
|---|---|---|
| Unit | yes, as behaviour tests and Node/Python tests | |
| API/contract | partial: `Test-SlackToolContract.ps1`, `contract.test.mjs`, `campaign-contract.test.mjs` | |
| Integration | partial: sync tests against synthetic profiles (`Test-SyncAgentHubRegistryRoot.ps1`, `Test-HostSurfaces.ps1`); whether any touch the live profile was not checked | |
| Playwright E2E | none for AgentHub itself; a demo-harness spec exists as a fixture (`packages/product-experience-engineering/kits/demo-harness/demo-harness.smoke.spec.ts`) | there is no UI |
| Role/authorization | n/a (no roles); dispatcher refusal rules covered by `Test-CodingAgentDispatch.ps1` | |
| Negative and recovery | several guard tests: `Test-PruneProtection.ps1`, `Test-ManagedJunctionRemoval.ps1`, `Test-ScriptsFailLoudly.ps1` | |
| Accessibility/responsive | n/a | |
| Security | `packages/security/scripts/*.test.mjs`, `Test-FileEncodingDiscipline.ps1` | no dependency scan on record; Dependabot PRs #10-#14 open |
| Performance | none | |
| AI evals | none; golden tasks per skill are a proposed enhancement | |

## Execution log

| Date (CT) | Command | Commit | Result |
|---|---|---|---|
| 2026-10-15 ~04:15 | `pwsh -NoProfile -File tests\Test-MobileScope.ps1` | `5002737` | **6/6 pass** (29 products classified, 2 frozen, 18 repos on the roster), 22.5 s |
| 2026-10-15 ~04:15 | `tests\Test-CapabilityOwnership.ps1` | `5002737` | **5/5 pass** (16 capabilities, 35 managed skill names) |
| 2026-10-15 ~04:15 | `tests\Test-CapabilityRouting.ps1` | `5002737` | **9/9 pass** |
| 2026-10-15 ~04:15 | `tests\Test-HostSurfaces.ps1` | `5002737` | **8/8 pass** |
| 2026-10-15 ~04:15 | `tests\Test-MarkdownFrontmatterValidation.ps1` | `5002737` | **6/6 pass** |
| 2026-10-15 ~04:15 | `tests\Test-FileEncodingDiscipline.ps1` | `5002737` | **7/8 pass, 1 FAIL**: four `Get-Content -Raw` reads without `-Encoding UTF8` in `tests/Test-RepoWiseBridge.ps1` (lines 98, 100, 118, 162), introduced by `fe74313`/`5af5f47` (2026-10-14/15). **Fixed in this change**; re-run recorded in the PR. |
| 2026-10-15 | `Run-AllTests.ps1`, `Validate-AgentHub.ps1` | `5002737` | **not run** (free RAM fell to 0.4 GB during this pass) |
| 2026-10-15T09:06Z | `tests\Test-FileEncodingDiscipline.ps1`, `Test-MarkdownFrontmatterValidation.ps1`, `Test-CrlfAnchors.ps1` | `5002737` + this change | **8/8, 6/6, 8/8 pass** (the encoding regression is cleared) |
| 2026-10-15T09:07Z | `tests\Test-RepoWiseBridge.ps1` (the file this change touched) | `5002737` + this change | **TIMEOUT at 300 s; not a pass.** The bridge unit suite reported `FAILED (failures=3, errors=1)` with `AssertionError: port 27766 did not become up`: fake servers did not come up in time on a CPU-saturated machine. The edit only adds `-Encoding UTF8` to four reads, which is already the default in PowerShell 7, so it does not change behaviour there. Re-run on an idle machine (tracked in Linear). Leftover processes from this run were stopped (own PIDs only). |

Historical evidence: no run log is committed in the repo (searched for logs and result files under `docs/`; none found). `docs/current-state.md` says "Verified 2026-08-08" but names no commit or command, so it is not usable as a test record.

## CI state

No GitHub Actions workflow on `main`. The only workflow GitHub knows is "Dependabot Updates" (checked via `gh api repos/shmindmaster/agenthub/actions/workflows`, 2026-10-15). The validate workflow was deleted on 2026-07-31 in `74504f2`; full history in [TECHNICAL.md](./TECHNICAL.md). Open PRs: #16 (overlay resolution from linked worktrees) and Dependabot #10 to #14, none with a CI check.

## What would raise the rung to Tested

Run `Validate-AgentHub.ps1` and `Run-AllTests.ps1` on a clean checkout at a recorded SHA, save the output, and add the counts to this file with commit and timestamp. Add the product-experience-engineering validators to the aggregate run. Whether to restore hosted CI is an owner decision: GitHub runner workflows were retired across the fleet in July and August 2026.
