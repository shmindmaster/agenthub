# Worktree management policy

This file is the single policy owner for Git worktree lifecycle decisions across Codex, Claude Code, Cursor, OpenCode, and other local agent hosts. Host instructions should point here instead of copying this policy.

## When to use a worktree

- A worktree is optional. Use the current checkout for ordinary sequential work.
- Use a worktree only when the user requests isolation, two tasks must run concurrently, or a risky change genuinely needs a separate checkout.
- Detect existing isolation first with `git rev-parse --show-toplevel`, `git rev-parse --git-dir`, and `git rev-parse --git-common-dir`. Never nest or manually replace a host-provided worktree.
- All coding agents use `C:\wt\<repo>\<task>` as the sole approved user-created worktree root. Keep names short. Do not create new worktrees beside portfolio repositories, directly under the user profile, or in `.wt` / `.worktrees` containers.
- Host-native worktree controls must use that same root where their documented settings support it. Repository automation verifies but never overwrites user-managed host settings. Where a host has no documented custom-root setting, the supported path is `scripts\New-AgentHubWorktree.ps1` plus the generated global policy (deployed by the controller with `scripts\agentctl.ps1 sync`), or manual Git under `C:\wt`; do not invent a setting. The helper consumes optional user-owned `AGENTHUB_WORKTREE_ROOT`, defaults it to `C:\wt`, and refuses any other resolved value.

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

- **Codex desktop** — its user-managed `git-worktree-root` is read-only verified as `C:\wt`. Repository automation must not replace the user setting. This machine keeps 5 managed worktrees.
- **Claude Desktop** — the user reports its **Settings > Claude Code > Worktree location** is `C:\wt`. This is a manual/UI verification boundary; repository automation cannot verify or overwrite it.
- **Claude Code CLI** — the official custom-location mechanism is a `WorktreeCreate` hook. `scripts\New-AgentHubWorktree.ps1` accepts the documented JSON payload (`cwd`, `name`) on stdin, creates `C:\wt\<repo>\<task>`, and prints that path last. The hook is declarative-ready and awaits controller installation after review; this repository change does not claim it is live. `worktree.baseRef` selects a base ref; it is not a root setting. A stale `activeWorktreeSession` path is session history, not proof of the configured root.
- **Qwen Code** — its built-in worktree path is fixed under `<repo>\.qwen\worktrees`. That mode is noncompliant and disabled for AgentHub-managed work; use the helper or manual Git under `C:\wt`. No custom setting key is asserted.
- **Cursor** — exposes machine-scoped `cursor.worktreeMaxCount` and `cursor.worktreeCleanupIntervalHours`. This shared policy does not assume those timers prove task ownership or authorize removal.
- **Manual Git and other host checkouts** — use the helper or create `C:\wt\<repo>\<task>` directly. Treat cleanup as owner-managed unless the creating host provides verifiable lifecycle ownership.
- Run `scripts\Audit-Worktrees.ps1` as a report-only audit. `C:\wt` is its only configured root. Historical home, sibling, `.wt`, `.worktrees`, and `%TEMP%` roots are explicitly labeled `forbidden-migration-source` and scanned only to support preservation-first migration review.
- Run `scripts\Remove-StaleWorktrees.ps1` for a separate cleanup review. Only registered worktrees beneath `C:\wt` can become eligible. The script re-checks live state: not a main tree, clean, fully pushed (`HEAD` on a remote), and idle for `-MinIdleHours` (default 12). Idle time is not ownership transfer. Actual removal requires both `-Apply` and the exact released worktree path in `-ApprovedPath`; it uses non-forced `git worktree remove` and stops on failure. Legacy and in-repository paths remain report-only. The script never raw-deletes a registered worktree or prunes metadata as a side effect.
