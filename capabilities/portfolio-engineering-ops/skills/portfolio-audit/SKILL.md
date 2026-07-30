---
name: portfolio-audit
description: Audit one or all repositories registered by AgentHub — git state, doc drift, tests, deployment config, executing-host config, and open PR status. Use when asked for a portfolio status check, health check, or "what's the state of X repo".
---

# Portfolio audit

Derive the repository inventory from AgentHub's registries instead of a
hard-coded portfolio list. Start with the repository identities in
`registry/automation-gates.json` (`portfolio[].id`) and merge any explicit
project paths from project registries such as
`registry/qwen-lsp-projects.json`. Resolve and de-duplicate candidates by
their Git common directory before treating a linked worktree as a separate
repository. If a registered identity has no resolvable path, report the
registry gap rather than silently dropping it or guessing a replacement.

## For one repo

Delegate to the `explorer` subagent (keeps file reads out of the main
context) with this checklist:
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

Dispatch one `explorer` subagent per registered repo in parallel (this is
genuinely separable, independent work — the right case for parallel
dispatch, not a single sequential pass). Collect each repo's checklist
result, then synthesize one compact table: repo | git state | open PRs |
executing-host config state | doc-drift flags | recommended next action.

## What NOT to do

Don't fix anything during an audit — report findings. If the user wants
fixes applied, that's a separate follow-up (use `docs-drift` for doc fixes,
`issue-to-pr` for code fixes). Don't touch any directory with uncommitted
changes without calling that out explicitly — active in-progress work is
not yours to modify during an audit.
