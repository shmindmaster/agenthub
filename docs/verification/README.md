# AgentHub Verification Pack

Evidence base: commit `5002737` (main, 2026-10-15 02:33 CT). Drafted 2026-10-15 from file reads, `git log` and `gh` read calls, plus six focused tests (five passed; one found a regression this change fixes). No build, install or sync was run. See [READINESS.md](./READINESS.md) for the verdict.

## Purpose

AgentHub is a portable control plane for skills, plugins, MCP servers and policy across coding-agent hosts. A desired-state registry (`registry/*.json`) drives validate, drift audit and apply, so each host's skills, MCP config and instruction files stay in line with one source. Entry points: `npx agenthub` (`scripts/agenthub-cli.mjs`) and `scripts/AgentHub.ps1`. The repo is public (`github.com/shmindmaster/agenthub`, checked via `gh api` 2026-10-15). Existing docs: [AGENTS.md](../../AGENTS.md), [docs/current-state.md](../current-state.md), [docs/development/testing.md](../development/testing.md), [docs/runbooks/sync-and-validate.md](../runbooks/sync-and-validate.md).

## Users

Engineers and platform teams who run more than one coding agent and need the agent estate to be governable: one owner per capability, parity proof per host, no silent drift, credentials kept out of transcripts. The repo's own `registry/agents.json` lists 22 active agent entries and 0 inactive. The control plane makes no model calls itself.

## Differentiation (as built, not as proven)

- Honest-state convention in registry data: `false` is checked-absent, `null` is not established (`AGENTS.md`, `registry/mcps.json:48`).
- Public core plus a gitignored personal overlay; core must not import overlay (`scripts/lib/CapabilityGraph.ps1`, `docs/current-state.md`).
- Every aggregate runner refuses to report success on an empty work set (`tests/Run-AllTests.ps1:49-51`, `scripts/AgentHub.ps1:248-251`).
- `sync -Apply` refuses to run unless validate passes first (`scripts/AgentHub.ps1:363-374`).

These are properties of the code. Whether they hold on a given commit is a test question; see [TESTS.md](./TESTS.md).

## Capability inventory

Ladder: Planned, Implemented, Integrated, Tested, Demonstrated, Production-Verified. "Tested" requires an executed result at a named commit. Only the registry checks (mobile scope, capability ownership and routing, host surfaces, frontmatter) have one in this pass ([TESTS.md](./TESTS.md#execution-log)); everything else stays at Implemented. "Integrated" needs a live trace; the only live-machine artefacts found are listed in [TECHNICAL.md](./TECHNICAL.md) and are not tied to a commit, so they do not raise a rung.

| Capability | Where | Rung reached | What would move it up |
|---|---|---|---|
| Registry validation (hashes, forbidden roots, schema) | `scripts/Validate-AgentHub.ps1` | Implemented (the registry tests it underpins pass: mobile scope, ownership, routing, host surfaces) | Run it at a recorded commit |
| Drift audit and apply across hosts | `scripts/Sync-AgentHub.ps1`, `Sync-Capabilities.ps1`, `Sync-Instructions.ps1`, `Sync-Subagents.ps1` | Implemented | An executed audit and apply on a throwaway profile, recorded with commit |
| Unified CLI (`init`, `validate`, `sync`, `drift`, `inventory`, `export`) | `scripts/agenthub-cli.mjs`, `scripts/AgentHub.ps1` | Implemented | A run of each command on a synthetic profile |
| Public-first overlay merge | `scripts/lib/CapabilityGraph.ps1`, `tests/Test-CapabilityOverlay.ps1` | Implemented | Run the overlay test; run audit with overlay on and off |
| MCP registry and per-host emission (15 servers in `registry/mcps.json`) | `registry/mcps.json`, `scripts/Sync-AgentHub.ps1` | Implemented | Declared-versus-deployed test run; protocol probe re-run |
| Policy compiler to host instruction files | `scripts/Sync-Instructions.ps1`, `policy-core.md` | Implemented | `Test-SyncInstructions.ps1` result; a rendered file diff |
| Coding-agent dispatcher | `packages/coding-agent-dispatch/skills/use-coding-agent/Invoke-CodingAgent.ps1` | Implemented | `-List` output captured; `Test-CodingAgentDispatch.ps1` result. `docs/current-state.md` itself says "prepared; deployment pending" |
| Fleet repo-standard checker | `scripts/Check-RepoStandard.ps1`, `registry/repo-standard.json` | Implemented | `Test-RepoStandard.ps1` result and a `-All` report |
| Media-studio release gates | `packages/media-studio/scripts/validate-demo-scenario.mjs` and siblings | Implemented | Node tests under `packages/media-studio/tests/` run |
| Slack capability contract | `packages/slack/mcp/` | Implemented | `contract.test.mjs` run; a live Slack call is a separate, externally-communicating step and out of scope here |
| RepoWise bridge | `packages/repowise/` | Implemented | `Test-RepoWiseBridge.ps1` and `test_repowise_bridge.py` run |
| Mobile-scope classification (agenthub itself is bucket `noNative`, `registry/mobile-scope.json:169-171`) | `registry/mobile-scope.json`, `tests/Test-MobileScope.ps1` | Implemented | Run `Test-MobileScope.ps1` |

## Pack contents

- [FUNCTIONAL.md](./FUNCTIONAL.md): roles, journeys, rules, errors.
- [TECHNICAL.md](./TECHNICAL.md): architecture, CI history, deployment form, critical trace.
- [COVERAGE.md](./COVERAGE.md): evidence matrix and gaps by kind.
- [TESTS.md](./TESTS.md): suite inventory, execution log, CI state.
- [DEMOS.md](./DEMOS.md): media inventory.
- [READINESS.md](./READINESS.md): status block and verdict.

Showcase assessment (linked, not copied): `reports/showcase/agenthub.md` in the local coding-agent-dispatch runtime folder (2026-10-14). It is a local file, not part of this repo.
