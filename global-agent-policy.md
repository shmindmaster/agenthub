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
- Use isolated worktrees only when parallel write isolation or repository policy requires them. The sole-approved-root rule and helper invocation below are load-bearing; consult them before creating or removing one.
- `C:\wt\<repo>\<task>` is the sole approved user-created worktree root. Use a documented native root control only when it resolves to `C:\wt`. Otherwise, do not invoke the host's native worktree command, flag, isolation mode, or UI; run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\New-AgentHubWorktree.ps1" -Cwd <repository-path> -Name <task-slug>` or use manual Git under `C:\wt`. The helper consumes the AgentHub-managed `AGENTHUB_WORKTREE_ROOT`, defaults it to `C:\wt`, and rejects every other resolved root.

## Capability ownership

- Reuse the owner recorded in `C:\Repos\shmindmaster\agenthub\registry\capabilities.json` before creating a skill, plugin, MCP server, role, hook, or wrapper.
- Prefer a shared MCP/API contract over duplicated host logic.
- Use official host formats. Record unsupported or undocumented packaging as discovery-required instead of inventing a format.
- Specialized roles and capabilities remain specialized; shared roles define coordination semantics, not feature ownership.

## Capability routing

- Parity across hosts is of outcome, validation, and delivery, not identical tools. Each host uses its strongest native capability for the same result.
- Never emulate through GUI clicks what a structured plugin, MCP tool, API, CLI, or native repository tool performs directly. Never install a redundant integration to imitate another platform's toolset.
- Prefer, in this order rather than as a hard tier list: native repository, shell, test, and version-control tools; then first-party plugins, skills, and MCP servers; then a first-party browser; then first-party GUI control; then direct APIs, SDKs, and CLIs; then specialized automation; then external augmentation. Reach past a step when it cannot produce the required outcome, and take the highest step that can.
- The host's own management CLI is a first-party surface and ranks with the rest. On Claude Code, `claude plugin validate` is the authoritative manifest check and `claude plugin disable` disables an enabled plugin without an interactive dialog; other hosts have their own equivalents, which are worth checking for. Confirm that a management surface is absent before working around it; assuming one does not exist has been wrong here before.
- Resolve a capability against `registry/fleet-profile.json` -> `hostSurfaces` for the surface actually in use, instead of inferring it from a product name. There, `null` means not established and `false` means checked and absent; neither is something to route to.
- Continuous execution, meaning continuing to the next required task without prompting, applies only where the host's own autonomy profile in `registry/fleet-profile.json` -> `autonomyProfiles` permits it. On a host whose default profile is `interactive`, ask instead. This narrows autonomy and never widens it: the escalation check under Engineering behavior applies on every host, whatever its profile.

## Provider availability

- Obey `registry/fleet-profile.json` dispatch policy before invoking an agent host, CLI, cloud runner, or API.
- Cursor IDE agents, Cursor Agent CLI, Cursor Cloud/Background Agents, and Cursor API sessions are active following explicit owner reauthorization on 2026-07-30.
- Give Cursor the same canonical capabilities, MCP ownership, worktree policy, review requirements, and drift enforcement as every other supported host. Use read-only account or local configuration checks for health evidence; do not consume a paid agent run merely to probe availability.

## Handoff

Report the outcome, changed files, validation evidence, branch or commit when applicable, remaining risks, and the next required gate. Silence or a missing automated review is not approval.
