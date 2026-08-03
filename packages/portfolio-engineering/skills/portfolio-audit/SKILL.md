---
name: portfolio-audit
description: Use when one or more registered repositories need a status or health audit covering git, documentation, tests, deployment, host configuration, and pull requests.
---

# Portfolio audit

For one repository, use its explicit path or the current working directory. For a portfolio audit,
enumerate immediate children of `C:\Repos\shmindmaster` that contain a `.git` directory or file,
then apply any repository paths explicitly supplied by the user. Resolve and de-duplicate candidates
by their Git common directory so a linked worktree is not reported as a separate product.

## For one repo

If the executing host supports read-only subagents, delegate this checklist to one fresh explorer
per repository. Otherwise, execute it directly. Every result must come from current repository
artifacts, not inherited session assumptions.

1. `git status --short`, `git branch --show-current`, `git rev-list
   --left-right --count origin/main...HEAD` — dirty tree, stale branch,
   unpushed/unpulled commits.
2. `gh pr list --state open` and `gh run list --limit 5` (if the repo has
   Actions) — open PRs, recent CI results.
3. Existing README, applicable repository instructions, docs, and the
   executing host's managed configuration — does a canonical instruction
   chain exist, and is any host-native bridge a thin import rather than a
   duplicate encyclopedia?
4. Package manifests vs. lockfiles vs. actual `node_modules`/`.venv` — any
   obvious drift (missing lockfile, uncommitted dependency change)?
5. Deployment config (Dockerfile, `.mcp.json`, CI workflows) vs. what the
   docs claim — flag contradictions, don't just repeat the docs.

## For "the whole portfolio"

When the executing host supports independent read-only subagents, dispatch one per repository in
parallel within the host's supported concurrency limits. Otherwise, execute the same checks
directly. Collect each result, then synthesize one compact table: repo | git
state | open PRs | executing-host config state | doc-drift flags |
recommended next action.

## What NOT to do

Don't fix anything during an audit — report findings. If the user wants
fixes applied, that's a separate follow-up (use `docs-drift` for doc fixes,
`issue-to-pr` for code fixes). Don't touch any directory with uncommitted
changes without calling that out explicitly — active in-progress work is
not yours to modify during an audit.
