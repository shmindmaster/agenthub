# Functional Description

Commit `5002737`. Everything below is read from code and docs. Nothing was executed in this pass.

AgentHub has no web UI and no end-user accounts. The "screens" are a command line and JSON or text reports.

## Roles and permissions

There is no in-product authentication. Authority comes from the operating-system user who runs the scripts and from the host config files that user can write.

| Role | What they do | Boundary that applies |
|---|---|---|
| Operator (repo owner) | Runs `validate`, `sync`, `sync --apply`, edits `registry/*.json` and `packages/` | Writes only to documented user-level host config paths (`docs/runbooks/sync-and-validate.md`); deployments never carry credentials |
| Adopter (new user) | `init` scaffolds a local overlay and profile from the examples | `init` rejects `-Apply` (`scripts/AgentHub.ps1:337-339`) |
| Orchestrator agent (Claude, Codex) | Calls the dispatcher to run work on another host | Dispatcher refuses hosts without a verified headless contract (`Invoke-CodingAgent.ps1:320-326`) |
| Dispatched agent host | Runs one headless task | Timeout kills the process tree (`Invoke-CodingAgent.ps1:479-491`) |

## Significant journeys

1. **Bootstrap.** `agenthub init` writes `overlays/personal/` and a profile from `overlays/personal.example/` and `agenthub.profile.example.json`. Entry: `scripts/AgentHub.ps1:336-340`, `Invoke-Init` at `:115`.
2. **Validate.** `agenthub validate` runs `scripts/Validate-AgentHub.ps1`: package existence, `canonicalSource` and `hashBasis` as repo-relative paths, content-hash match (`:240-248`), forbidden roots, stale paths.
3. **Drift audit.** `agenthub sync` (or `drift`) runs four scripts in audit mode: `Sync-Instructions`, `Sync-Subagents`, `Sync-Capabilities`, `Sync-AgentHub` (`scripts/lib/SyncOrchestrator.ps1:7-20`). Output is console text plus `latest-drift.json` in the AgentHub runtime folder.
4. **Deploy.** `agenthub sync --apply` validates first and refuses on failure (`scripts/AgentHub.ps1:363-374`), then runs the same four scripts with `-Apply`. Skills are copied verbatim (`Sync-Capabilities.ps1:239`). Managed-file hashes are recorded in `managed-skills.json`.
5. **Export a clean public tree.** `agenthub export <dir>` calls `scripts/Export-PublicCore.ps1` (a residue audit, not a dual-repo sync; its header says so).
6. **Synthetic demo profile.** `scripts/AgentHubDemoProfile.ps1` builds an isolated profile with `AGENTHUB_OVERLAY=off` (`:143-146`), documented in `docs/runbooks/demo-profile.md`. This is the route for any recording.
7. **Dispatch.** `Invoke-CodingAgent.ps1 -List` returns each host as `callable`, `routed` or `refused`; a run is headless with a default 1800 s timeout (`:48`).
8. **Fleet standard check.** `Check-RepoStandard.ps1 -All` reports, `-Fix` repairs deterministic drift in member repos.

## Business rules (as coded)

- `false` means checked and absent; `null` means not established. `revision: null` must carry a reason (`registry/mcps.json:48`).
- Core must not import overlay; Validate fails if a private tree remains under `packages/` (`docs/current-state.md`, Public-first entry).
- Apply never overwrites a managed file the user modified unless adoption is requested (`Sync-Capabilities.ps1:233`).
- Apply refuses when no agent is active (`Sync-Capabilities.ps1:100`).
- Content hashes normalize line endings so two checkouts at the same commit agree (`Sync-Capabilities.ps1:103-` comment; `scripts/RegistryContentHash.ps1`).
- A test run that discovers zero files fails (`tests/Run-AllTests.ps1:49-51`).
- Bare `-Validate` is read-only; only `-Apply` writes (`Sync-AgentHub.ps1:2599`).

## AI and agent behaviour

The control plane makes no model calls. Model use happens only in dispatched hosts. The dispatcher routes by registry (`registry/fleet-profile.json`, autonomy profiles) and refuses GUI hosts and remote cloud agents (`Invoke-CodingAgent.ps1:9-12`). `docs/current-state.md` marks the dispatcher "prepared; deployment pending" and says two hosts passed bounded smokes on free models; those smoke results are not in this repo. Commit `f9c99e0` (2026-10-14) enables five more hosts "after bounded smokes"; the smoke logs are also not in the repo.

## Data in and out

| Data | Direction | Location |
|---|---|---|
| Registry JSON (13 files, about 6,600 lines) | in | `registry/` |
| Package content (16 capability packages) | in | `packages/`, `registry/capabilities.json` |
| Private overlay | in, never committed | `overlays/personal/` (gitignored) |
| Host config, skill folders, instruction files | out | per-host user-level paths from `registry/agents.json` templates |
| Sync state, drift report, managed-skills inventory | out | AgentHub runtime `sync/` folder: `sync-state.json`, `latest-drift.json`, `managed-skills.json` |

## Error handling and recovery

- Validation failure blocks apply (`AgentHub.ps1:371`).
- A delegated script that did not run counts as failure, shown as `MISSING` (`:244`).
- A user-modified managed destination is skipped and listed as a failure, not overwritten.
- Recovery is by re-running audit and apply; stale managed files are removed only under `-Apply`, and the state file is rebuilt per apply (`Sync-AgentHub.ps1:237-241`).
- No rollback snapshot of host configs was found: `grep backups scripts/*.ps1` matches nothing. Recovery is re-apply from the registry. A `backups` folder exists in the local runtime directory but nothing in `scripts/` writes to it (the writer, if any, is unidentified).

## Gaps

See [COVERAGE.md](./COVERAGE.md) and [READINESS.md](./READINESS.md). Functional gaps: no UI, no receipt browser, no approval step bound to a dispatch prompt, and docs lag (`docs/current-state.md` header says "Verified 2026-08-08" while the file describes 2026-10-14 work).
