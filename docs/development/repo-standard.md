# Fleet Repository Standard

Canonical statement of the repository knowledge + agent-instruction standard
for every owned repo under `C:\Repos\shmindmaster` (the roster in
`registry/repo-standard.json`). Mechanically enforced by
[`scripts/Check-RepoStandard.ps1`](../../scripts/Check-RepoStandard.ps1) with
the roster in [`registry/repo-standard.json`](../../registry/repo-standard.json).
Supersedes every per-repo legacy instruction layout (2026-08-08).

## The model

```text
README.md     human orientation and quick start
AGENTS.md     the ONLY human-authored agent contract
CLAUDE.md     adapter: @AGENTS.md + @.claude/CLAUDE.md (RepoWise-managed block)
docs/         curated durable knowledge (this taxonomy)
RepoWise      derived intelligence (ONE workspace at C:\Repos)
tests/CI      executable enforcement
tracker       the one backlog authority named in AGENTS.md
```

## Root files

- `AGENTS.md` sections (checked anchors): `## Mission`,
  `Knowledge authority`, `Start here`, `RepoWise` workflow,
  `Canonical commands`, `## Tracker`, `Definition of done`, `## Safety`.
  Ceiling: 400 lines — a contract and router, not an encyclopedia.
- `CLAUDE.md` contains `@AGENTS.md` and `@.claude/CLAUDE.md` imports and at
  most 8 authored content lines. RepoWise regenerates its managed section
  (`.claude/CLAUDE.md`) on update; never hand-edit below the
  `REPOWISE:START` marker.
- Forbidden anywhere in a repo: `GEMINI.md`, `.cursorrules`, `.windsurfrules`,
  `.github/copilot-instructions.md`, `docs/ai/REPO_AGENT_RULES.md`,
  `NEXT_SESSION.md`, `STATUS.md`, `output.txt`, `lint_output.txt`.
  Hosts that need repo instructions read `AGENTS.md` natively (Cursor CLI,
  Codex, Cline, Copilot cloud agent) or are configured once at machine level
  (Gemini `contextFileName` includes `AGENTS.md`). Adapt tools to the
  standard, never repos to every tool.
- Root markdown beyond the allowlist (README/AGENTS/CLAUDE/CHANGELOG/
  CONTRIBUTING/SECURITY/CODE_OF_CONDUCT/LICENSE, plus `global-agent-policy.md`
  here) is scratch: fold into `docs/` or delete.

## docs/ taxonomy

`docs/README.md` (router: what each doc contains, when to read it, what
authority it has), `docs/current-state.md` (verified reality only — date
claims, say explicitly what is unverified), `docs/product/`,
`docs/architecture/` (+ `decisions/`), `docs/development/`,
`docs/runbooks/`, `docs/plans/` (`PLANS.md`, `active/`, `completed/`).

Local Markdown links in every repo doc are audited by the checker: a link
target must exist, and file links (`[](.../file.md)`) must resolve to a
file while directory links (`[](.../dir/)`, trailing slash) must resolve
to a directory. A trailing `/` or `/.` is stripped before resolution.

## Nested AGENTS.md

Only where commands, invariants, or validation genuinely differ. Must state
the root `AGENTS.md` applies and carry local deltas only; restating the root
contract (Mission + Knowledge authority + Definition of done) is drift.

## RepoWise

- One workspace at `C:\Repos` (`.repowise-workspace.yaml`) covers git repos
  under `shmindmaster`, `sh-pendoah`, `musa-dev-team`, and `pendoah`.
  Rostered shmindmaster membership is checked against that file (path leaf
  or alias).
- Every rostered member repo has the post-commit hook installed and gitignores
  `.repowise/` and `.claude/CLAUDE.md`.
- Index freshness: `.repowise/state.json` `last_sync_commit` == `HEAD`
  (the hook normally maintains this). Indexes themselves live in each repo's
  `.repowise/` directory.
- One MCP registration: `repowise-workspace` in `registry/mcps.json`
  (`repowise mcp C:/Repos`). A repo-local `.mcp.json` mentioning repowise
  is drift. (Tool-managed `.vscode/mcp.json` written by `repowise update`
  is allowed.)
- Excluded from the workspace: `.demo-workspace` (product-demo-studio
  capture output; not a git repo — do not delete).
- The knowledge-standard checker still applies only to rostered
  shmindmaster repos; client trees are indexed, not standardized.

## Tracker authority

Each repo names one: `linear` (SH- IDs), `github-issues` (OSS repos), or
`none` (small sites/tools; `docs/plans/` covers complex work). No repo-local
competing backlogs; plans reference tracker IDs, never duplicate status.

## Deferred fleet items (2026-08-28)

`Check-RepoStandard.ps1 -All` runs 504 checks across the 17 managed
repositories. As of 2026-08-28, AgentHub itself is clean; the remaining
failures live in five client/personal repos that have not yet been scoped.
Each is listed here with its owning repo and the evidence that pins it, so no
failure is unexplained. Clearing them is follow-up work owned by the named
repo, not by the fleet checker.

| Repo | Failure | Owner | Evidence / remediation |
| --- | --- | --- | --- |
| abacare | `root-scratch: .api.log`, `.seed.log` | abacare | Remove the two root log files (they are runtime scratch, not source). |
| abacare | `docs-file: docs/README.md`, `docs/current-state.md`, `docs/plans/PLANS.md` missing | abacare | Create the required docs skeleton (`scripts/Check-RepoStandard.ps1 -Repo abacare -Fix` can author it). |
| abacare | `repowise-freshness: index not at HEAD` | abacare | `repowise update --repo abacare` (or confirm the post-commit hook is installed). |
| crewscore | `docs-dir: docs/product`, `docs/architecture`, `docs/development`, `docs/runbooks` missing | crewscore | Create the required docs directories. |
| crewscore | `broken-link: docs\cli.md -> ./crewscore.svg` | crewscore | Add the missing SVG or fix the link target in `docs/cli.md`. |
| lexalign | `nested-refs-root: apps\web\AGENTS.md` | lexalign | Make the nested AGENTS.md state that the root AGENTS.md applies. |
| lexalign | `repowise-freshness: index not at HEAD` | lexalign | `repowise update --repo lexalign`. |
| rexa | `root-scratch: vlc-help.txt` | rexa | Remove the root scratch file. |
| saroshhussain | `root-scratch: baseline-run.log`, `test-run.log`, `verify-run.log` | saroshhussain | Remove the three root run logs. |

## Checker usage

```powershell
pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All          # report
pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -Repo <name>  # one repo
pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All -Fix     # repair deterministic drift
pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All -Format json
```

`-Fix` only: deletes forbidden files, creates missing docs skeleton
files/dirs, adds `.gitignore` entries. It never authors `AGENTS.md` content
and never deletes unlisted files — knowledge folding is agent judgment, not
checker behavior.
