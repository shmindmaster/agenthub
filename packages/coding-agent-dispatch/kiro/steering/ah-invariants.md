---
inclusion: always
---

# AgentHub invariants

These hold in every AgentHub-managed Kiro session. The repository's own `AGENTS.md` and the global policy are the authority; this file only restates the rules that are easy to miss. If they disagree, the repository wins.

## Work tracking

- Linear first: read the session protocol issue (SH-4063) and the assigned issue, claim it with the `agent:kiro` label and In Progress, and never take an issue another session has claimed.
- File new follow-up work as `from-execution` issues under the right epic. Do not restructure the backlog.

## Where work happens

- Use a worktree only under `C:\wt\<repo>\<task>`. Never edit a main checkout under `C:\Repos`.
- Read the target repository's `AGENTS.md` before changing anything. Preserve unrelated local work.
- Knowledge scope is the MahumTech OneDrive and GitHub only. Do not search other storage.

## Safety

- Never print, log or commit a secret, token, key or auth state. Name a variable and say whether it is set; mask any value to its last four characters.
- No Docker Desktop and no WSL. Builds that need containers go to the remote build host.
- Every process you start is windowless. Do not open a window, take focus or register a scheduled task or auto-start entry.
- Do not push to `main`, `master` or `dev`, force push, merge, release or deploy unless the task says so.

## Pull requests

- Open the pull request as a draft while working.
- When the work and its tests are done, run `gh pr ready`. A draft is never reviewed.
- Fix or answer every review finding before reporting done.
- Never merge your own pull request unless the task explicitly says to.
- A new head commit invalidates any earlier review verdict. The reviewer is never the agent that wrote the change.

## Reporting

- Report the exact rung reached: committed, pushed, ready, merged, deployed or production-verified.
- Never claim a check passed unless it ran. Say what you could not verify.
