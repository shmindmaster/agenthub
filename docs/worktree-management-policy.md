# Worktree management policy

This file is the single policy owner for Git worktree lifecycle decisions across Codex, Claude Code, Cursor, OpenCode, and other local agent hosts. Host instructions should point here instead of copying this policy.

## When to use a worktree

- A worktree is optional. Use the current checkout for ordinary sequential work.
- Use a worktree only when the user requests isolation, two tasks must run concurrently, or a risky change genuinely needs a separate checkout.
- Detect existing isolation first with `git rev-parse --show-toplevel`, `git rev-parse --git-dir`, and `git rev-parse --git-common-dir`. Never nest or manually replace a host-provided worktree.
- All coding agents use `C:\wt\<repo>\<task>` as the sole approved user-created worktree root. Keep names short. Do not create new worktrees beside portfolio repositories, directly under the user profile, or in `.wt` / `.worktrees` containers.
- Host-native worktree controls must use that same root where their settings support it. Do not overwrite user-managed host settings from a repository script.

## Creation and generated files

- Record the creator/host, source repository, branch or detached commit, purpose, and expected removal condition.
- Do not run dependency installation or a full build automatically. Run only the minimum setup required by the task. Read-only reviews should start with Git diff and static inspection.
- Treat `node_modules`, `.next`, `dist`, `build`, `.turbo`, coverage, and test-results as disposable per-worktree output, never as source of truth.
- On Windows, keep fallback paths short even when `core.longpaths=true`; shell scripts and non-Git tools can still fail on long paths.

## Safe removal

1. Identify the owning repository with `git worktree list --porcelain`.
2. Inspect `git status --short`, the branch/detached state, unpushed commits, and any untracked files.
3. Preserve required work by committing, pushing, or making an explicit patch/bundle approved for the task.
4. Run `git worktree remove <path>` from the main repository. Do not use raw recursive deletion for a registered worktree.
5. If removal fails, stop. Do not continue to prune metadata or delete the branch.
6. Verify the path is gone and the registration no longer appears before deleting a branch.
7. Use `git worktree prune --dry-run` first. Pruning removes stale administrative records; it is not a substitute for removing a live checkout.

Never clean up a worktree owned by another active task unless the user explicitly transfers ownership. Dirty, untracked, unpushed, pinned, or in-progress worktrees are protected.

## Retention and audit

Native per-host behavior and user-managed location verification as of July 2026:

- **Codex desktop** — its user-managed **Settings > Worktrees** location has been set to `C:\wt` by the user. The application defaults to `$CODEX_HOME\worktrees`, but repository automation must not replace the user setting. This machine keeps 5 managed worktrees.
- **Claude Desktop / Claude Code** — its user-managed worktree location has been set to `C:\wt` by the user. `cleanupPeriodDays` remains **7**; its periodic sweep covers clean subagent/background worktrees only and never explicit `--worktree` sessions. Dirty, untracked, or unpushed work remains protected.
- **Cursor** — exposes machine-scoped `cursor.worktreeMaxCount` and `cursor.worktreeCleanupIntervalHours`. This shared policy does not assume those timers prove task ownership or authorize removal.
- **Manual Git and other host checkouts** — treat cleanup as owner-managed unless the creating host provides verifiable lifecycle ownership. Observed sibling and `%TEMP%\opencode` worktrees are not assumed safe merely because they are clean or old.
- Run `scripts\Audit-Worktrees.ps1` as a report-only audit. Review its output before any removal. Cleanup is always a separate, explicit operation.
- Run `scripts\Remove-StaleWorktrees.ps1` for a separate cleanup review. It re-checks live state and reports technical eligibility: not a main tree, clean, fully pushed (`HEAD` on a remote), and idle for `-MinIdleHours` (default 12). Idle time is not ownership transfer. Actual removal requires both `-Apply` and the exact released worktree path in `-ApprovedPath`; it uses non-forced `git worktree remove` and stops on failure. The script never raw-deletes a registered worktree or prunes metadata as a side effect.
