# Worktree management policy

This file is the single policy owner for Git worktree lifecycle decisions across Codex, Claude Code, Cursor, OpenCode, and other local agent hosts. Host instructions should point here instead of copying this policy.

## When to use a worktree

- A worktree is optional. Use the current checkout for ordinary sequential work.
- Use a worktree only when the user requests isolation, two tasks must run concurrently, or a risky change genuinely needs a separate checkout.
- Detect existing isolation first with `git rev-parse --show-toplevel`, `git rev-parse --git-dir`, and `git rev-parse --git-common-dir`. Never nest or manually replace a host-provided worktree.
- All coding agents use `C:\wt\<repo>\<task>` as the sole approved user-created worktree root. Keep names short. Do not create new worktrees beside portfolio repositories, directly under the user profile, or in `.wt` / `.worktrees` containers.
- Host-native worktree controls must use that same root where their documented settings support it. The controller verifies user-managed native roots and deploys only AgentHub-owned helpers, hooks, generated instructions, workflows, and documented opt-out settings. Where a host has no documented custom-root setting, do not invoke its native worktree command, flag, isolation mode, or UI. Use the deployed `C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\New-AgentHubWorktree.ps1`, or manual Git under `C:\wt`; do not invent a setting. The helper consumes controller-managed `AGENTHUB_WORKTREE_ROOT`, defaults it to `C:\wt`, and refuses any other resolved value.

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

Native per-host behavior and enforcement as verified on July 29, 2026:

- **Codex Desktop 0.144.4** — its user-managed `git-worktree-root` is read-only verified as `C:\wt`. The controller must not replace the user setting.
- **Claude Desktop / CLI 2.1.220** — the user reports Desktop's **Settings > Claude Code > Worktree location** is `C:\wt`. CLI uses the documented `WorktreeCreate` hook and the deployed AgentHub helper. `worktree.baseRef` selects a base ref; it is not a root setting.
- **Qwen Code 0.21.1** — native worktrees and subagent isolation are fixed under `<repo>\.qwen\worktrees`; do not use them.
- **OpenCode CLI/Desktop 1.18.9** — its experimental native API stores worktrees under OpenCode's global data directory and exposes no custom-root argument. Do not relocate all OpenCode data; use the helper.
- **Gemini CLI 0.53.0** — its fixed `<repo>\.gemini\worktrees` mode is disabled with `experimental.worktrees=false`.
- **Hermes 0.19.0** — its fixed `<repo>\.worktrees` mode is disabled with `worktree: false`; do not pass `-w`.
- **GitHub Copilot CLI 1.0.76** — `/worktree`, `/move`, and its hidden worktree flag have no custom-root setting. Keep `experimental=false` and use the helper.
- **Antigravity 1.1.8 / Desktop 2.4.3 / IDE 2.1.1** — create the checkout with AgentHub first, open the returned path, and select Local Mode. New Worktree mode has no documented root control and is prohibited.
- **Grok 0.2.114** — set new-session and fork worktree modes to `never`; worktree subagent isolation remains prohibited by generated instructions.
- **Warp** — the managed parameterized TOML Tab Config invokes the deployed helper and opens its returned path. Warp's general worktree root is not configurable.
- **Cline 3.0.47** — its `--worktree` path is fixed under `~\.cline\worktrees`; do not use the flag. CLI and Desktop consume their documented global rule locations.
- **Qoder 1.1.5** — its public docs do not define the `WorktreeCreate` event found in installed binary strings. The hook remains discovery-required and is not installed; do not use `--worktree`.
- **Cursor** — exposes machine-scoped `cursor.worktreeMaxCount` and `cursor.worktreeCleanupIntervalHours`. This shared policy does not assume those timers prove task ownership or authorize removal.
- **Manual Git and other host checkouts** — run the helper with `-Cwd <repository-path> -Name <task-slug>` or create `C:\wt\<repo>\<task>` directly. Treat cleanup as owner-managed unless the creating host provides verifiable lifecycle ownership.
- Run `scripts\Install-WorktreePolicy.ps1` to audit deployment and add `-Apply` to deploy reviewed local controls after backup. Run `scripts\agentctl.ps1 sync -Apply` for generated global instructions. Both commands fail closed on conflicting, user-owned destinations.
- Run `scripts\Audit-Worktrees.ps1` as a report-only audit. `C:\wt` is its only configured root. Historical home, sibling, `.wt`, `.worktrees`, and `%TEMP%` roots are explicitly labeled `forbidden-migration-source` and scanned only to support preservation-first migration review.
- Run `scripts\Remove-StaleWorktrees.ps1` for a separate cleanup review. Only registered worktrees beneath `C:\wt` can become eligible. The script re-checks live state: not a main tree, clean, fully pushed (`HEAD` on a remote), and idle for `-MinIdleHours` (default 12). Idle time is not ownership transfer. Actual removal requires both `-Apply` and the exact released worktree path in `-ApprovedPath`; it uses non-forced `git worktree remove` and stops on failure. Legacy and in-repository paths remain report-only. The script never raw-deletes a registered worktree or prunes metadata as a side effect.
