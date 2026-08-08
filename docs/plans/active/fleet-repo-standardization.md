# Plan: Fleet Repository Standardization (2026-08-08)

## Purpose / outcome

Every owned repo under `C:\Repos\shmindmaster` conforms to the fleet
repository standard ([docs/development/repo-standard.md](../../development/repo-standard.md)):
one authored agent contract (`AGENTS.md`), adapter `CLAUDE.md`, curated
`docs/` taxonomy, RepoWise workspace membership with fresh index, explicit
tracker authority, and no legacy instruction surfaces.

## Verified state at start (2026-08-08)

- 18 git repos in the container; `awesome-mcp-servers` excluded (external
  fork on PR branch), `.demo-workspace` excluded (not a repo). **17 in scope.**
- RepoWise 0.39.0 installed via `uv tool install repowise`; workspace created;
  hooks installed in all 17; MCP probe OK (protocol 2025-06-18).
- Checker built and fixture-tested (11/11) as part of this plan.

## Target

`Check-RepoStandard.ps1 -All` exits 0; `repowise status -w` shows all repos
indexed and fresh; one bootstrap commit per repo on `main`.

## Exclusions

- No changes to awesome-mcp-servers or .demo-workspace.
- No deployment changes (no CI/CD/prod mutations).
- Unrelated dirty work in member repos is preserved untouched
  (explicit-path staging; never `git add -A` in dirty repos).

## Repo roster and worker routing

| Repo | Model tier | Notes |
| --- | --- | --- |
| agenthub | coordinator | this plan; checker + registry + skill done first |
| abacare, coledger, lawli, lexalign, subops, verigence, warrantygains, sabhi | deepseek-v4-pro | large/sensitive monorepos; sabhi has in-flight studio deletion — do not touch those paths; its CLAUDE.md edits are mid-standardization by owner |
| mahumtech, saroshhussain, shtrial, tgiagency, gitpin, crewscore | deepseek-v4-flash | mechanically standard |
| rexa | coordinator (last) | already ~standard; ACTIVE writer in tree — defer until their FSRS work lands |
| Repairs | kimi-k2.7-code | on demand |

## Milestones

1. [x] RepoWise workspace + hooks + MCP registration + capability + skill.
2. [x] Checker + fixture tests + roster.
3. [x] agenthub standardized (this commit).
4. [ ] Worker migrations ×16 with evidence artifacts.
5. [ ] Fleet sweep: checker `-All` green, repowise doctor/status clean.
6. [ ] Final evidence report.

## Validation per milestone

- M1: `repowise workspace list`; MCP initialize probe.
- M2: `tests/Test-RepoStandard.ps1` 11/11.
- M3: `Validate-AgentHub.ps1` + `Run-AllTests.ps1` + checker self-check.
- M4: per-repo checker pass + commit on `main`.
- M5: checker `-All` exit 0; `repowise status -w` fresh.

## Risks / rollback

- Knowledge loss on deletion → fold-then-delete; git history is the archive.
- Active writer in rexa → rexa deferred; re-check before its turn.
- sabhi/warrantygains in-flight deletions → workers stage only their own paths.
- Rollback per repo: `git revert` the bootstrap commit.

## Decision log

- 2026-08-08: CLAUDE.md = two imports (`@AGENTS.md`, `@.claude/CLAUDE.md`)
  because `repowise update` regenerates its managed block at
  `.claude/CLAUDE.md` by default; root file stays authored and stable.
- 2026-08-08: one workspace MCP via agenthub registry; per-repo repowise MCP
  entries declared drift.
- 2026-08-08: `.repowise/` and `.claude/CLAUDE.md` gitignored everywhere;
  tool-managed `.vscode/mcp.json` may be committed.
