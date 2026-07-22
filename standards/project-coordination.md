# Project Coordination Standard

`AGENTS.md` is the primary tool-neutral instruction file for a repository. Tool-specific instruction files adapt to it and must not introduce competing policy.

Use this lightweight sequence when the corresponding systems are in the authorized task scope:

1. Read repository instructions and the assigned issue.
2. Inspect repository status, active branches, worktrees, and pull requests.
3. Claim a bounded change set and choose an isolated branch or worktree when needed.
4. Implement while preserving unrelated work.
5. Run repository verification and capture evidence.
6. Create or update the pull request.
7. Update the linked tracker item.
8. Merge or deploy only when explicitly authorized and all required gates are met.

GitHub is the canonical source-control surface. Linear is the preferred issue surface when a task is linked there. Personal agent coordination belongs under `state/cross-agent/`, never in a client tracker.
