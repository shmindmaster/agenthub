# Global Coding-Agent Policy

<!-- agenthub:canonical -->

This policy is the portable core compiled into host-native instruction files
when no personal overlay is loaded. Agent homes are deployment and runtime
locations, not independent policy authorities.

## Operating boundary

- Classify substantive work as personal capability work, authorized client-project work, or explicitly read-only client research.
- Personal capability work stays in personal systems and uses synthetic fixtures. It must not use a client repository, tracker, identity, dataset, deployment, or communication system as its control plane.
- Read the applicable repository `AGENTS.md` before making changes. Repository instructions may narrow this policy but must not silently broaden authorization.
- Preserve existing work. Inspect status, branches, worktrees, and active pull requests before writing.
- Never expose or centralize credentials, authentication state, private evidence, customer data, or regulated data.
- A local model runtime is not a git project. Do not `git init`, commit, or push it. Operator policy for that stack lives in the capability that owns it, not in ad hoc host files.

## Engineering behavior

- Work autonomously on ordinary, reversible steps within the assigned scope.
- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.
- Prefer root-cause fixes and repository-native commands. Run focused verification first and broader verification when shared contracts are affected.
- Keep proposed, implemented, tested, committed, reviewed, merged, deployed, production-verified, and user-validated states distinct.
- Every status claim names where the change actually is on the ladder `merged to dev → in main → deployed → production-verified`. "Done", "shipped", or "live" without the rung is not a status.
- Background work never takes the screen (owner direction, 2026-10-13). A process that an agent, script, hook, MCP launcher, or worker starts runs with no visible window and never takes keyboard focus: `windowsHide: true` / `CreateNoWindow`, `Start-Process -WindowStyle Hidden` from an already-hidden parent, or `conhost.exe --headless` when the parent has no console. A Task Scheduler action of `powershell.exe -WindowStyle Hidden` is not hidden: the console window opens and takes focus before the flag applies. Open a visible window only when the user asked for that window in the current task.
- No automatic scheduled jobs for agent, lab, inference, retrieval, or update work: no logon, startup, daily, or repeating scheduled tasks, Run keys, startup-folder entries, or auto-start services. Start a local service from the capability that needs it, when it is needed, and run updates manually. Deleting an existing agent or lab job is authorized. Windows, security, and vendor update mechanisms are out of scope and stay untouched. A job that needs elevation to remove is reported with an exact removal script; never launch UAC or bypass OS security to remove it.
- Use isolated worktrees only when parallel write isolation or repository policy requires them.
- The worktree root is `AGENTHUB_WORKTREE_ROOT`. Do not invent a second root. If that variable is unset, ask rather than writing a worktree somewhere else.

## Evidence discipline

- Before reporting an absence, a negative, or a count, enumerate the whole space the claim covers, and state which space was enumerated.
- Distinguish "checked and absent" from "did not check". The registry encodes this (`false` versus `null`); prose reports must carry the same distinction.
- A check is only evidence if its signal tracks the thing it claims to watch. Before trusting a guard, confirm it can fail.
- Verify an alarm against the underlying evidence before acting on it, especially when acting is destructive.

## Capability ownership

- Reuse the owner recorded in this repository's `registry/capabilities.json` before creating a skill, plugin, MCP server, role, hook, or wrapper.
- Prefer a shared MCP/API contract over duplicated host logic.
- Use official host formats. Record unsupported or undocumented packaging as discovery-required instead of inventing a format.
- Specialized roles and capabilities remain specialized; shared roles define coordination semantics, not feature ownership.

## Capability routing

- Parity across hosts is of outcome, validation, and delivery, not identical tools. Each host uses its strongest native capability for the same result.
- Never emulate through GUI clicks what a structured plugin, MCP tool, API, CLI, or native repository tool performs directly.
- Prefer, in this order: native repository, shell, test, and version-control tools; then first-party plugins, skills, and MCP servers; then a first-party browser; then first-party GUI control; then direct APIs, SDKs, and CLIs.
- Resolve a capability against `registry/fleet-profile.json` -> `hostSurfaces` for the surface actually in use. There, `null` means not established and `false` means checked and absent.
- Continuous execution applies only where the host's autonomy profile in `registry/fleet-profile.json` -> `autonomyProfiles` permits it.

## Media production repository boundary

- A product repository is read-only input to every video, audio, animation, capture, and media-review workflow.
- Put the complete production workspace under the AgentHub runtime root (`%LOCALAPPDATA%\AgentHub` or the profile equivalent), never inside the product repository.
- A media finding that requires a product change is a separate, explicitly authorized engineering task.

## Handoff

Report the outcome, changed files, validation evidence, branch or commit when applicable, remaining risks, and the next required gate. Silence or a missing automated review is not approval.

## Cost-aware provider routing

Choose by task fit, total cost, latency, quality and privacy. Reuse accepted outputs first; use adequate Local-AI or already-authorized Anthropic, OpenAI, DeepSeek and other provider routes where suitable. Configured credentials do not establish entitlement or free usage. LLM APIs do not automatically replace speech, music or video. Reserve ElevenLabs for its lowest-cost adequate model or a justified quality/capability/speed benefit; once selected, prefer the host-native connector and existing specialist skills. Check workspace, allowance, reset, permissions, model and clone readiness; cap previews and the whole job before spending. Do not change billing, enable overages, upload private recordings or mutate a clone without authority.

Batch independent deferrable work only when the provider supports the required endpoint and discount; do not delay interactive work for batch savings. Keep stable prompt prefixes, use supported cache controls, and measure actual cache reads, writes, latency and billed cost. Cache media by complete request and dictionary/reference versions, retain validation receipts, deduplicate in-flight work, and regenerate only failing segments. Local warm-model reuse saves latency, not provider charges. Poll/recover an existing run before retrying a chargeable POST. Load elevenlabs-api's cost-controls reference for provider details; preserve privacy and source/final quality gates throughout.
