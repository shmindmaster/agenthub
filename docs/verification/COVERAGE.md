# Coverage and Evidence Matrix

Commit `5002737`. A cell says what exists in the repo. "Test: file exists, not run" means no executed result is on record for this pass. "Demo: none" means no recording was found ([DEMOS.md](./DEMOS.md)). "Deploy: no SHA" means the installed copy does not record a commit ([TECHNICAL.md](./TECHNICAL.md)).

## Evidence matrix

| Capability | Journey | UI | Backend | Integration | Test | Demo | Deploy |
|---|---|---|---|---|---|---|---|
| Registry validate | Validate | CLI text | `scripts/Validate-AgentHub.ps1` | none (local files) | No test file named for it; referenced by 10 files in `tests/` (e.g. `Test-RegistryContentHash.ps1`, `Test-RegistryHostReferences.ps1`, `Test-AgentHubEntryPoint.ps1`); not run | none | n/a (runs from checkout) |
| Drift audit | Audit | CLI text, `latest-drift.json` | `Sync-AgentHub.ps1` and three siblings | Host config files on the operator machine | `Test-SyncAgentHubIdempotency.ps1`, `Test-SyncCapabilities.ps1`, `Test-SyncInstructions.ps1`, `Test-SyncSubagents.ps1`, `Test-HostSurfaces.ps1`; not run | none | Local artefacts exist (2026-10-15 00:37 CT), no SHA |
| Apply / deploy | Deploy | CLI text | same | same | `Test-SyncAgentHubRegistryRoot.ps1`, `Test-ManagedJunctionRemoval.ps1`, `Test-PruneProtection.ps1`, `Test-InactiveHostDeployment.ps1`; not run | none | Last recorded apply 2026-10-14 19:05 CT, no SHA |
| CLI wrapper | all | `npx agenthub` | `scripts/agenthub-cli.mjs` | needs `pwsh` | `Test-AgentHubEntryPoint.ps1`; not run | none | n/a |
| Overlay merge | Bootstrap | CLI | `scripts/lib/CapabilityGraph.ps1`, `tests/lib/PrivateOverlay.ps1` | none | `Test-CapabilityOverlay.ps1`, `Test-CapabilityOwnership.ps1`; not run | none | n/a |
| Policy compile | Audit/Deploy | host instruction files | `Sync-Instructions.ps1`, `policy-core.md` | host files | `Test-SyncInstructions.ps1`, `Test-RenderLineEndingIndependence.ps1`, `Test-CrlfAnchors.ps1`; not run | none | no SHA |
| MCP emission | Deploy | host MCP configs | `Sync-AgentHub.ps1` | 15 servers declared | `Test-DeclaredVsDeployedMcp.ps1`, `Test-McpLauncherDirectness.ps1`, `Test-LocalMcpHostScope.ps1`, `Test-TomlEmission.ps1`; not run | none | no SHA |
| Dispatcher | Dispatch | CLI `-List` | `Invoke-CodingAgent.ps1` | other agent hosts' CLIs | `Test-CodingAgentDispatch.ps1`; not run. Bounded host smokes are cited in commit `f9c99e0`; logs not in repo | none | `docs/current-state.md`: "prepared; deployment pending" |
| Repo-standard checker | Fleet check | CLI report | `Check-RepoStandard.ps1` | other repos on disk | `Test-RepoStandard.ps1`; not run | none | n/a |
| Slack capability | (external) | none | `packages/slack/mcp/*.mjs` | Slack Web API (live) | `contract.test.mjs`, `Test-SlackCapability.ps1`, `Test-SlackToolContract.ps1`, `Test-SlackHostParity.ps1`; not run | none | no SHA |
| Media-studio gates | (media) | none | `packages/media-studio/scripts/*.mjs` | ffmpeg, Playwright, voice providers | 4 `*.test.mjs`, `Test-MediaStudio*.ps1`; not run | none | no SHA |
| RepoWise bridge | (code intel) | none | `packages/repowise/` | RepoWise server, local | `Test-RepoWiseBridge.ps1` + `test_repowise_bridge.py`; not run | none | no SHA |

## Integration map

| Integration | Kind | Verification level |
|---|---|---|
| Host config files (JSON/TOML) for 22 active agent entries | local file write | Implemented. Observed `latest-drift.json` statuses are unlinked to a commit |
| MCP servers (15 in `registry/mcps.json`) | declared, per-host emit | Implemented. Protocol revision recorded per server by probe; probes not re-run here |
| Slack Web API | external, live | Implemented. Live call not made (external-communicating) |
| ElevenLabs, Firecrawl, DigitalOcean, CodeRabbit packages | capability content | Implemented (content only). No live call verified |
| GitHub (repo, Dependabot) | remote | Verified by read: repo public, one workflow (Dependabot). No CI |
| Linear projects P-SH-21 and P-SH-22 | tracking | Both "Planned" per the operator; not read by the pack |

## UI without backend

None. There is no UI.

## Backend without UI

All of it. Notably: dispatcher receipts, parity heatmap and MCP-migration lab are proposed in the showcase (enhancements 1 to 3) and not built.

## Untested integrations (no executed result)

Everything. Specifically no executed result for: host config emission per host, Slack bridge, dispatcher against any host, RepoWise bridge, media gates.

## Works-locally-only

The whole product. It acts on the operator machine's user-level paths. There is no hosted deployment. Two things are tied to this machine and cannot be reproduced from the repo: the applied state under the local AgentHub runtime folder and the gitignored personal overlay.

## Test-discovery gaps (found while building this matrix)

- `packages/product-experience-engineering/tests/run-all.ps1` runs `validate-runtime.ps1`, `validate-demo-readiness.ps1` and `validate-kits.ps1` (which runs the execution-controls Python unit tests and, if env is set, a strict `tsc`). `Run-AllTests.ps1` only picks up `validate-plugin.ps1` (`tests/Run-AllTests.ps1:32-47`), and `validate-plugin.ps1` does not call the others (grep). So these checks, and `kit.test.ts` / `schema.test.ts`, are outside the aggregate runner.
- `Run-AllTests.ps1` ignores `tests/Test-AppiumSessionCleanup.mjs` and `Test-MobileLabGuestStart.mjs` directly; `Test-MobileDevelopment.ps1` references both by name, so they are probably reached indirectly. Not traced.
