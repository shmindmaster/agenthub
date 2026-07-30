# Shared Codex Guidance

<!-- agenthub:managed -->

# Global Coding-Agent Policy

<!-- agenthub:canonical -->

This policy is compiled into host-native instruction files. Agent homes are deployment and runtime locations, not independent policy authorities.

## Operating boundary

- Classify substantive work as personal capability work, authorized client-project work, or explicitly read-only client research.
- Personal capability work stays in personal systems and uses synthetic fixtures. It must not use a client repository, tracker, identity, dataset, deployment, or communication system as its control plane.
- Read the applicable repository `AGENTS.md` before making changes. Repository instructions may narrow this policy but must not silently broaden authorization.
- Preserve existing work. Inspect status, branches, worktrees, and active pull requests before writing.
- Never expose or centralize credentials, authentication state, private evidence, customer data, or regulated data.

## Engineering behavior

- Work autonomously on ordinary, reversible steps within the assigned scope.
- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.
- Prefer root-cause fixes and repository-native commands. Run focused verification first and broader verification when shared contracts are affected.
- Keep proposed, implemented, tested, committed, reviewed, merged, deployed, production-verified, and user-validated states distinct.
- Use isolated worktrees only when parallel write isolation or repository policy requires them. Follow `C:\Repos\shmindmaster\agenthub\docs\worktree-management-policy.md` before creating or removing one.
- `C:\wt\<repo>\<task>` is the sole approved user-created worktree root. Use a documented native root control only when it resolves to `C:\wt`. Otherwise, do not invoke the host's native worktree command, flag, isolation mode, or UI; run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\New-AgentHubWorktree.ps1" -Cwd <repository-path> -Name <task-slug>` or use manual Git under `C:\wt`. The helper consumes the AgentHub-managed `AGENTHUB_WORKTREE_ROOT`, defaults it to `C:\wt`, and rejects every other resolved root.

## Capability ownership

- Reuse the owner recorded in `C:\Repos\shmindmaster\agenthub\registry\capabilities.json` before creating a skill, plugin, MCP server, role, hook, or wrapper.
- Prefer a shared MCP/API contract over duplicated host logic.
- Use official host formats. Record unsupported or undocumented packaging as discovery-required instead of inventing a format.
- Specialized roles and capabilities remain specialized; shared roles define coordination semantics, not feature ownership.

## Provider holds

- Obey `registry/fleet-profile.json` dispatch policy before invoking an agent host, CLI, cloud runner, or API.
- Cursor IDE agents, Cursor Agent CLI, Cursor Cloud/Background Agents, and Cursor API sessions are **paused for the current quota window**, not retired. The account is funded and configured; its spend headroom for this billing period is simply used up, and the window is expected to reset in early August 2026. Treat this as "not right now," not "not this tool."
- While the pause is in force, do not invoke, probe, or route work to Cursor. To lift it: confirm from billing/usage data (never a paid probe) that the window has actually reset, then make one reviewed control-plane change setting `dispatchPolicy.cursor.enabled` and `dispatchPolicy.cursor-agent.enabled` to Boolean `true`, setting `providerHolds.cursor.active` to Boolean `false`, updating this section, and synchronizing regenerated instructions.

## Handoff

Report the outcome, changed files, validation evidence, branch or commit when applicable, remaining risks, and the next required gate. Silence or a missing automated review is not approval.
