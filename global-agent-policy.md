# Global Coding-Agent Policy

<!-- agenthub:canonical -->

This policy is compiled into host-native instruction files. Agent homes are deployment and runtime locations, not independent policy authorities.

## Operating boundary

- Classify substantive work as personal capability work, authorized client-project work, or explicitly read-only client research.
- Personal capability work stays in personal systems and uses synthetic fixtures. It must not use a client repository, tracker, identity, dataset, deployment, or communication system as its control plane.
- Read the applicable repository `AGENTS.md` before making changes. Repository instructions may narrow this policy but must not silently broaden authorization.
- Preserve existing work. Inspect status, branches, worktrees, and active pull requests before writing.
- Never expose or centralize credentials, authentication state, private evidence, customer data, or regulated data.
- `D:\Local-AI` is a local runtime, not a git project. Do not `git init`, commit, or push it. Operator policy and skills for that stack live in AgentHub (`packages/local-ai`).

## Engineering behavior

- Work autonomously on ordinary, reversible steps within the assigned scope.
- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.
- Prefer root-cause fixes and repository-native commands. Run focused verification first and broader verification when shared contracts are affected.
- Keep proposed, implemented, tested, committed, reviewed, merged, deployed, production-verified, and user-validated states distinct.
- Use isolated worktrees only when parallel write isolation or repository policy requires them. The sole-approved-root rule and helper invocation below are load-bearing; consult them before creating or removing one.
- `C:\wt\<repo>\<task>` is the sole approved user-created worktree root. Use a documented native root control only when it resolves to `C:\wt`. Otherwise, do not invoke the host's native worktree command, flag, isolation mode, or UI; run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\New-AgentHubWorktree.ps1" -Cwd <repository-path> -Name <task-slug>` or use manual Git under `C:\wt`. The helper consumes the AgentHub-managed `AGENTHUB_WORKTREE_ROOT`, defaults it to `C:\wt`, and rejects every other resolved root.

## Evidence discipline

- Before reporting an absence, a negative, or a count, enumerate the whole space the claim covers, and state which space was enumerated. Reporting "no X exists" after inspecting one directory, one component, or one key space has repeatedly been wrong here — a single-component sample never establishes a system-wide claim.
- Distinguish "checked and absent" from "did not check". The registry encodes this (`false` versus `null`); prose reports must carry the same distinction rather than presenting an unchecked thing as a settled one.
- A check is only evidence if its signal tracks the thing it claims to watch. Before trusting a guard, monitor, or gate, confirm it can fail — one that has never fired, or that measures a quantity the current operation does not change, is decoration.
- Verify an alarm against the underlying evidence before acting on it, especially when acting is destructive or interrupts expensive work.

## Capability ownership

- Reuse the owner recorded in `C:\Repos\shmindmaster\agenthub\registry\capabilities.json` before creating a skill, plugin, MCP server, role, hook, or wrapper.
- Prefer a shared MCP/API contract over duplicated host logic.
- Use official host formats. Record unsupported or undocumented packaging as discovery-required instead of inventing a format.
- Specialized roles and capabilities remain specialized; shared roles define coordination semantics, not feature ownership.

## Capability routing

- Parity across hosts is of outcome, validation, and delivery, not identical tools. Each host uses its strongest native capability for the same result.
- Never emulate through GUI clicks what a structured plugin, MCP tool, API, CLI, or native repository tool performs directly. Never install a redundant integration to imitate another platform's toolset.
- Prefer, in this order rather than as a hard tier list: native repository, shell, test, and version-control tools; then first-party plugins, skills, and MCP servers; then a first-party browser; then first-party GUI control; then direct APIs, SDKs, and CLIs; then specialized automation; then external augmentation. Reach past a step when it cannot produce the required outcome, and take the highest step that can. Between two first-party providers of the same capability, prefer the one the running surface already provides over one a local process must be started to provide: `registry/mcps.json` -> `activationPolicy` prefers remote over local, one shared local process over per-host copies, and a capability-invoked start over a session-start one.
- The host's own management CLI is a first-party surface and ranks with the rest. On Claude Code, `claude plugin validate` is the authoritative manifest check and `claude plugin disable <plugin>` disables an enabled plugin without an interactive dialog: the argument is optional in its usage line, so naming the plugin is what makes the command non-interactive. Other hosts may have their own equivalents. Confirm that a management surface is absent before working around it; assuming one does not exist has been wrong here before.
- Resolve a capability against `registry/fleet-profile.json` -> `hostSurfaces` for the surface actually in use, instead of inferring it from a product name. There, `null` means not established and `false` means checked and absent; neither is something to route to.
- Continuous execution, meaning continuing to the next required task without prompting, applies only where the host's own autonomy profile in `registry/fleet-profile.json` -> `autonomyProfiles` permits it. On a host whose default profile is `interactive`, ask instead. This narrows autonomy and never widens it: the escalation check under Engineering behavior applies on every host, whatever its profile.

## Mobile scope

- `registry/mobile-scope.json` is the sole authority for which products may receive native mobile work. Resolve the product against it before any mobile action. A product absent from it is not eligible; stop and ask rather than inferring eligibility from an active repository, a live domain, or an owner remark.
- For a product this file places in `excludedPendingReposition`, do not create, configure, publish, register, reserve, or modify any Expo project, EAS project, Apple bundle identifier, App Store Connect app, Google Play application or package, Firebase mobile application, APNs or FCM credential, mobile deep-link association, store metadata, mobile branding, or native application code. Their current product names, domains, and package identifiers are non-canonical and temporary. A placeholder identifier is a prohibited identifier.
- This is a freeze on long-lived identity, not a scheduling preference: an Apple bundle identifier cannot be changed after the first build is uploaded to App Store Connect, and Android treats a changed `applicationId` as a different application. Only the owner lifts a freeze, and only by the `exitCondition` recorded against that product.
- Mobile platform conventions for eligible products live in the `mobile-platform-standard` skill. Read it before mobile work; do not reconstruct the baseline from memory.

## Owner voice

- The owner's own speaking voice is a local capability. Never generate it, or attempt to approximate it, through a hosted TTS provider: a cloud provider cannot produce that speaker and returns a different one that merely sounds professional. Route it through the Local-AI control plane and keep the audio on the machine.
- Owner-voice audio, and any corpus derived from it, is not training data for an external service and is not transmitted for benchmarking. Comparing against a hosted provider sends only benchmark *text*, and needs the same explicit approval as any other outbound transmission.
- Every owner-voice generation passes a speaker-identity gate before it is delivered, embedded in a video, or sent to anyone. Identity is measured against the owner's own recordings, not assumed from the fact that the correct route was used. Expression, emotion, and pacing are adjustable; speaker identity is the fixed constraint they are adjusted within.
- Do not correct pronunciation by respelling input text. It measurably degrades speaker identity. Pronunciation is a dictionary layer applied at render time and shared across engines.

## Provider availability

- Obey `registry/fleet-profile.json` dispatch policy before invoking an agent host, CLI, cloud runner, or API.
- Cursor IDE agents, Cursor Agent CLI, Cursor Cloud/Background Agents, and Cursor API sessions are active following explicit owner reauthorization on 2026-07-30.
- Give Cursor the same canonical capabilities, MCP ownership, worktree policy, review requirements, and drift enforcement as every other supported host. Use read-only account or local configuration checks for health evidence; do not consume a paid agent run merely to probe availability.

## Opportunity evidence

When preparing job applications, consulting proposals, RFP responses, capability
statements, resumes, cover letters, technical pitches, interview preparation, or
other role/proposal materials, retrieve evidence first. You are already the
writer; do not start or call a local chat LLM (`ai.ps1 start llamacpp`, Ollama
chat, Open WebUI generation, or `:8787/v1/chat/completions`) to draft the
artifact.

- **Qdrant `knowledge`** (Local-AI, host `127.0.0.1:16333`, via
  `use-knowledge-access` / `Search-Knowledge.ps1 -Semantic` /
  `D:\Local-AI\query.ps1 --index knowledge`) is the primary store for project
  history, capabilities, proposal material, career evidence, and business
  context. Do not query alias `legal` for this work.
- **RepoWise** (`use-repowise`, workspace `C:\Repos`) is the store for
  repository architecture, implementations, APIs, infrastructure, and other
  code-backed examples.
- Combine them: Qdrant for breadth and history; RepoWise for concrete
  engineering evidence. Search iteratively if the first hits are thin. Prefer
  specific, transferable examples over generic capability claims. Translate
  technical work into outcomes (scale, latency, reliability, cost, delivery).
- Load `opportunity-engine` to parse the opportunity, match evidence, gate
  claims, and render. Fail closed on unsourced numbers and uncleared client
  names.

## Handoff

Report the outcome, changed files, validation evidence, branch or commit when applicable, remaining risks, and the next required gate. Silence or a missing automated review is not approval.
