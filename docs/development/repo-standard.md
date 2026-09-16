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

A repository may keep an intentional flat `docs/` layout only when its roster
entry declares `docsExemptions` with an exact list of otherwise-required paths
and a nonblank reason. The checker rejects paths outside the global required
file/directory lists and emits each accepted exemption as a visible passing
evidence row. This is for authoritative compact layouts, not unfinished docs.

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
  `.repowise/`. It must also ignore either the exact generated adapter
  `.claude/CLAUDE.md` or the entire `.claude/` directory when that repository
  deliberately treats all Claude-local state as generated and untracked.
- Index freshness: `.repowise/state.json` `last_sync_commit` == `HEAD`
  (the hook normally maintains this). Indexes themselves live in each repo's
  `.repowise/` directory.
- One MCP registration: `repowise-workspace` in `registry/mcps.json`
  (`repowise mcp C:/Repos`). A repo-local `.mcp.json` mentioning repowise
  is drift. Tool-managed `.vscode/mcp.json` / `.cursor/mcp.json` may exist
  but must invoke `repowise mcp C:/Repos`, never the member checkout.
  `Check-RepoStandard.ps1` fails a member path (measured 2026-09-10 when
  `repowise update --repo agenthub` from inside the repo wrote
  `C:/Repos/shmindmaster/agenthub`).
- Excluded from the workspace: `.demo-workspace` (media-studio
  capture output; not a git repo — do not delete).
- The knowledge-standard checker still applies only to rostered
  shmindmaster repos; client trees are indexed, not standardized.

## Tracker authority

Each repo names one: `linear` (SH- IDs), `github-issues` (OSS repos), or
`none` (small sites/tools; `docs/plans/` covers complex work). No repo-local
competing backlogs; plans reference tracker IDs, never duplicate status.

## Fleet exceptions and deferred items (2026-08-30)

`Check-RepoStandard.ps1 -All` currently runs 540 checks across 18 managed
repositories. AgentHub itself is clean. Intentional exceptions remain exact,
reasoned, and machine-visible; they are not failures.

| Repo | Failure | Owner | Evidence / remediation |
| --- | --- | --- | --- |
| abacare | Intentional flat ten-document layout | AgentHub registry | Explicit, reasoned `docsExemptions`; no placeholder taxonomy is generated. |
| crewscore | Intentional flat OSS documentation layout | AgentHub registry | Explicit, reasoned `docsExemptions`; code examples are not treated as links. |
| lexalign | Generated `apps\web\AGENTS.md` | AgentHub registry | Exact `agentsExemptions` entry; Next.js recreates the file and identifies its generator in the file. |

Three failures remain in two repositories with active unrelated work. They
stay visible rather than being force-cleared or hidden by a broad exception.

| Repo | Failure | Owner | Evidence / remediation |
| --- | --- | --- | --- |
| abacare | `repowise-freshness: index not at HEAD` | abacare | Refresh after its four active web-file changes are resolved or explicitly adopted. |
| lienwise | `.gitignore` omits `.claude/CLAUDE.md`; RepoWise index is stale | lienwise | Resolve with the repository owner because `.claude/CLAUDE.md` is tracked and currently modified. |

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
