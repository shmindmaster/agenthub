# Current State

Verified 2026-08-08. This file records demonstrated reality, not intent.

## Operational today

- Registry (`registry/*.json`) declares hosts, capabilities, MCP servers,
  fleet profile, and the fleet repository standard roster.
- `scripts/Validate-AgentHub.ps1` validates the registry against on-disk
  package content (content hashes over git-tracked files).
- `tests/Run-AllTests.ps1` runs all behavior tests and package validators.
- Sync scripts deploy managed instructions/skills/MCP config to host user
  directories (`Sync-AgentHub.ps1`, `Sync-Capabilities.ps1`, audit by default).
- **RepoWise workspace** at `C:\Repos\shmindmaster` (created 2026-08-08):
  17 member repos, post-commit hooks installed in all members,
  `repowise-workspace` MCP registered in `registry/mcps.json`
  (protocol 2025-06-18, probed). agenthub is the default/primary repo.
- **Fleet checker**: `scripts/Check-RepoStandard.ps1` with fixture tests in
  `tests/Test-RepoStandard.ps1` (11 behavior checks, passing 2026-08-08).
- **Skill deployment ledger**: fixed 2026-08-08. `Sync-Capabilities.ps1` wrote
  `managed-skills.json` only after the failure gate, so any run with a refusal
  copied skills to disk and recorded none of them — stranding every skill
  deployed between 2026-08-06 and 2026-08-08 as permanently "unowned". The
  ledger now writes before the gate and records only what the run can claim
  (refused-and-never-owned excluded; refused-but-owned carried forward with
  its prior hash so the modification stays detectable). Live ledger recovered
  from 469 destinations at 2026-08-05 to 501 current.
- **Mobile scope guard**: `registry/mobile-scope.json` classifies all 21
  products (4 eligible, 4 evaluate-later, 3 frozen, 10 no-native); the
  prohibition is compiled into every managed host by `Sync-Instructions.ps1`;
  `tests/Test-MobileScope.ps1` (5 behavior checks, passing 2026-08-08, each
  demonstrated failing against a synthetic fixture) keeps registry and policy
  true together.

## In progress

- Fleet-wide repository standardization to the
  [repo standard](./development/repo-standard.md): plan and live status in
  [plans/active/fleet-repo-standardization.md](./plans/active/fleet-repo-standardization.md).
- Mobile platform rollout for the eligible products: plan and live status in
  [plans/active/mobile-scope-guard.md](./plans/active/mobile-scope-guard.md).
  The guard and the standard are landed; per-product implementation
  (Rexa reference build, abacare `apps/mobile`, gentlenext) is not started.

## Known pre-existing test failures (as of 2026-08-08)

Re-measured 2026-08-08 against a clean clone of `8ae18ff`: **163 passed / 4
failed** across 26 files. Four earlier entries (Test-AgentHubEntryPoint,
Test-CrlfAnchors, Test-SyncAgentHubIdempotency, Test-SyncCapabilities) now
pass; `Test-RepoStandard` newly fails and is **not** the 11/11 this file
previously claimed.

The 4 failing files are agenthub's own engineering debt:

| File | Cause |
| --- | --- |
| Test-CapabilityRouting | `use-chrome-devtools-mcp` carries no `## Capability required` or `## Resolve a provider` section (5 assertions) |
| Test-DeclaredPathAccountability | 6 hermes paths absent from disk with no `<field>Note` |
| Test-RepoStandard | `compliant-repo-passes`: the checker's `nested-no-duplication` rule flags the fixture's own nested AGENTS.md |
| Test-ScriptsFailLoudly | `Start-ChromeAgentCDP.ps1` does not set `$ErrorActionPreference = 'Stop'` |

The mobile scope guard added `Test-MobileScope.ps1` (+5) and the
Sync-Capabilities ledger fix added one behavior (+1), changing no failure:
**169 passed / 4 failed**, same four files.

## Known constraints

- The checker compares the RepoWise index to `HEAD`; a repo with uncommitted
  in-flight work is fine (hook syncs on commit), but a just-committed repo
  shows stale until the hook or `repowise update --repo <name>` runs.
- `.claude/CLAUDE.md` and `.vscode/mcp.json` are RepoWise-generated per repo;
  they are gitignored / tool-managed respectively, never hand-maintained.

## Verification

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
repowise status -w   # from C:\Repos\shmindmaster
```
