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
  products (5 eligible, 4 evaluate-later, 2 frozen, 10 no-native); the
  prohibition is compiled into every managed host by `Sync-Instructions.ps1`;
  `tests/Test-MobileScope.ps1` (5 behavior checks, passing 2026-08-08, each
  demonstrated failing against a synthetic fixture) keeps registry and policy
  true together.
- **LienWise rename (2026-08-08)**: the product frozen by the mobile guard on
  2026-08-07 was repositioned and renamed. The owner rewrote all 296 commits
  with `git filter-repo` and force-pushed, so the retired name is absent from
  content, filenames, and commit messages across the whole history — verified
  independently here. Fleet references (`repo-standard.json`,
  `mobile-scope.json`, the DigitalOcean portfolio/DNS skills, the
  product-demo-studio compatibility table, the product-experience-engineering
  leak guard, and the RepoWise workspace) now say `lienwise`. The freeze exit
  condition was met, so it moved to `include` (P1). **Pre-rewrite SHAs are
  dead**: any other checkout needs `git fetch && git reset --hard origin/main`.
- **What a history rewrite does not reach** (measured on lienwise 2026-08-08,
  and true of any future rename): `git push --force` rewrites branches only.
  Three surfaces survive it and are worth checking before declaring a rename
  complete.
  - **Unmerged branches.** `lienwise/m0-rebrand-and-domain` still descended
    from pre-rewrite history and carried the retired name in **343 files and
    46 commit messages**. Verified superseded (its 8 unique files were older
    docs and `CLAUDE.md` adapters that `main` replaced), then deleted.
  - **`refs/pull/*/head`.** All **163** carried it; **zero** were reachable
    from `main`. GitHub keeps these as immutable PR snapshots — no push
    removes them. 8 merged PR titles also still name the product. Left alone
    deliberately: editing a title whose own diff still says the old name makes
    the record incoherent, and the refs beneath it are permanent regardless.
  - **Gitignored working files.** `backend/.env` still pointed at a dead
    `sabhi_dev` database, and `frontend/out`, `.next`, `test-evidence`, and
    `test-results` held pre-rename output. None are tracked, so no rewrite
    touches them. Repointed at the compose database; artifacts deleted.
  - Clean end state: `git ls-remote` shows `refs/heads/main` and nothing else.

- **Third-party plugin tracking (2026-08-08)**: `registry/native-connectors.json`
  -> `thirdPartyPlugins` records plugins the fleet uses but does not own, with
  the official channel and last-observed version per host.
  `tests/Test-ThirdPartyPlugins.ps1` (6 behaviors, each demonstrated failing
  against a synthetic fixture) fails if a lagging host names no fix, if an
  absent host explains no reason, or if a tracked plugin is ever republished
  from AgentHub's own marketplace. First tracked plugin is **superpowers**
  (obra/superpowers, MIT): current at 6.2.0 on claude, codex, antigravity, and
  grok; **behind on cursor (6.1.1) and qoder (5.1.0)**, both in-app owner
  actions. AgentHub does not vendor it — `hostPrivateExtensionPolicy` withholds
  install authority for claude and codex, and mirroring would cut the host off
  from the upstream release stream.

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
| Test-DeclaredPathAccountability | 4 hermes paths absent from disk with no `<field>Note` |
| Test-ScriptsFailLoudly | `Start-ChromeAgentCDP.ps1` does not set `$ErrorActionPreference = 'Stop'` |

The mobile scope guard added `Test-MobileScope.ps1` (+5) and the
Sync-Capabilities ledger fix added one behavior (+1), changing no failure:
169 passed / 4 failed.

**`Test-RepoStandard` was the fourth, and is fixed as of 2026-08-08.** It was
never fixture noise. `Check-RepoStandard.ps1` compared `Get-ChildItem`'s
`FullName` against a path built from the configured `fleetRoot`; those two
disagree whenever the root is spelled differently on disk — an 8.3 short path
(`C:\Users\SAROSH~1\...`, which is exactly what `$env:TEMP` returns here), a
`subst` drive, a symlink. The root `AGENTS.md` then failed the "is this the root
file" test and was audited as a nested one, with its relative path sliced at the
wrong offset (`iant\AGENTS.md`). `Get-Item` expands 8.3; `Resolve-Path` does not.
Two further findings from the same pass: the `nested-refs-root` rule accepted only
two exact phrasings and rejected lienwise's perfectly clear "Root contract still
applies: [`../AGENTS.md`]", and the whole nested-AGENTS rule had **no fixture
coverage at all**, which is why both defects sat unnoticed. Three behaviors added,
covering pass, fail, and the root-is-not-nested case. Suite now **179 passed /
3 failed**. `Test-ThirdPartyPlugins.ps1` then
added six more: **175 passed / 4 failed** across 28 files, still the same four.

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
