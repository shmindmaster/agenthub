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

## In progress

- Fleet-wide repository standardization to the
  [repo standard](./development/repo-standard.md): plan and live status in
  [plans/active/fleet-repo-standardization.md](./plans/active/fleet-repo-standardization.md).

## Known pre-existing test failures (as of 2026-08-08)

`tests/Run-AllTests.ps1` has 7 failing files that fail identically on the
commit preceding the standardization work (verified against a clean HEAD
clone, 125 passed / 7 failed): Test-AgentHubEntryPoint, Test-CapabilityRouting,
Test-CrlfAnchors, Test-DeclaredPathAccountability, Test-ScriptsFailLoudly,
Test-SyncAgentHubIdempotency, Test-SyncCapabilities. They are agenthub's own
engineering debt (capability-routing sections missing from
use-chrome-devtools-mcp, hermes path notes, Start-ChromeAgentCDP strictness,
Sync-AgentHub Get-FileHash resolution in test harnesses) — not caused by the
standardization, which fixed Validate-AgentHub to green.

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
