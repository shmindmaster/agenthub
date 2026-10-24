# Global Coding-Agent Policy

<!-- agenthub:canonical -->

This is the public, portable global policy compiled into host-native instruction files. A deployment that carries owner-specific rules keeps them in the gitignored personal overlay (`overlays/personal/global-agent-policy.md`), which replaces this file for that machine. Agent homes are deployment and runtime locations, not independent policy authorities.

## Operating boundary

- Classify substantive work as personal capability work, authorized client-project work, or explicitly read-only client research.
- Personal capability work stays in personal systems and uses synthetic fixtures. It must not use a client repository, tracker, identity, dataset, deployment, or communication system as its control plane.
- Read the applicable repository `AGENTS.md` before making changes. Repository instructions may narrow this policy but must not silently broaden authorization.
- Preserve existing work. Inspect status, branches, worktrees, and active pull requests before writing.
- Never expose or centralize credentials, authentication state, private evidence, customer data, or regulated data.
  This includes diagnostic output: never echo an environment variable's raw value, a config file holding a
  key, or a request header. Print the variable's name and whether it is set, and mask any value to its last
  four characters.
- A deployed local model runtime is not a git project. Do not `git init`, commit, or push it. Find its canonical source repository and **patch the source, never the deployed copy**: a fix applied to a deployed copy survives only until the next deploy overwrites it, silently.

## Engineering behavior

- Work autonomously on ordinary, reversible steps within the assigned scope.
- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.
- Prefer root-cause fixes and repository-native commands. Run focused verification first and broader verification when shared contracts are affected.
- Keep proposed, implemented, tested, committed, reviewed, merged, deployed, production-verified, and user-validated states distinct.
- Every status claim names where the change actually is on the ladder `merged to dev → in main → deployed → production-verified`. "Done", "shipped", or "live" without the rung is not a status.
- Background work never takes the screen. A process that an agent, script, hook, MCP launcher, or worker starts runs with no visible window and never takes keyboard focus: `windowsHide: true` / `CreateNoWindow`, `Start-Process -WindowStyle Hidden` from an already-hidden parent, or `conhost.exe --headless` when the parent has no console. A Task Scheduler action of `powershell.exe -WindowStyle Hidden` is not hidden: the console window opens and takes focus before the flag applies. Open a visible window only when the user asked for that window in the current task.
- No automatic scheduled jobs for agent, lab, inference, retrieval, or update work: no logon, startup, daily, or repeating scheduled tasks, Run keys, startup-folder entries, or auto-start services. Start a local service from the capability that needs it, when it is needed, and run updates manually. Deleting an existing agent or lab job is authorized. Windows, security, and vendor update mechanisms are out of scope and stay untouched. When an authorized removal requires administrator rights, prepare the exact removal script and use native Windows elevation with owner authorization. The owner approves the Windows consent prompt; never bypass OS security or change account privileges.
- Use isolated worktrees only when parallel write isolation or repository policy requires them.
- The worktree root is `AGENTHUB_WORKTREE_ROOT`. Do not invent a second root. If that variable is unset, ask rather than writing a worktree somewhere else. Create worktrees with the AgentHub worktree helper (`scripts/New-AgentHubWorktree.ps1`), which rejects every other resolved root.

## Evidence discipline

- Before reporting an absence, a negative, or a count, enumerate the whole space the claim covers, and state which space was enumerated. A single-component sample never establishes a system-wide claim.
- Distinguish "checked and absent" from "did not check". The registry encodes this (`false` versus `null`); prose reports must carry the same distinction rather than presenting an unchecked thing as a settled one.
- A check is only evidence if its signal tracks the thing it claims to watch. Before trusting a guard, monitor, or gate, confirm it can fail — one that has never fired, or that measures a quantity the current operation does not change, is decoration.
- Verify an alarm against the underlying evidence before acting on it, especially when acting is destructive or interrupts expensive work.

## Capability ownership

- Reuse the owner recorded in this repository's `registry/capabilities.json` before creating a skill, plugin, MCP server, role, hook, or wrapper.
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

## Media production repository boundary

- A product repository is read-only input to every video, audio, animation, capture, and media-review workflow. Media agents must not create or modify source code, tests, Playwright specs, Remotion compositions, dependencies, configuration, seed fixtures, assets, manifests, evidence, generated media, or Git state in the product repository.
- Put the complete production workspace under the AgentHub runtime root (`%LOCALAPPDATA%\AgentHub\media-studio` or the profile equivalent), never inside the product repository. A legacy product-video config may be read from a repository, but it must never be created or updated there; copy or translate it into the external job workspace.
- A media finding that requires a product change produces Product-Readiness Feedback. Product remediation is a separate, explicitly authorized engineering task with its own scope and verification; never perform it as a media-pipeline stage.
- Delivered video files are named `NN - Title.mp4` with no product prefix, and a delivered series carries a `README.md` index in its folder. Each product or purpose has exactly one flat folder in the video library; every file sits directly in it, with no subfolders (no training, notes, evidence or archive folders). When a master is superseded, delete it and every reproducible intermediate outright; do not create `_retired`, `_old`, or archive folders. A wrong section is re-recorded and the master re-cut; never deliver an addendum clip.
- A product or engineering change told on video is a technical story: `media-studio` `references/technical-story.md` owns the shape (show what happened, explain why, show where, say why it matters). When the picture is a running product, `references/product-picture.md` owns the picture: Playwright WebM + Recast (pointer, click, zoom, visible result), not Ken Burns stills mixed with Remotion cards.

## Video and content quality

These rules apply to every host making video or demo content and sit on top of the rules above; load `media-studio` for the workflow.

- Product honesty comes before film. Record the real pain, buyer, competitor and native-platform overlap, usage, and a one-line reason anyone should care. A weak product is rebuilt, repositioned, retired, or repurposed into a vertical rather than polished on film.
- Narration and picture are one coordinated experience: voice first, so each scene lasts as long as its narration. The named screen is visible by the line's first content word, the named action lands within about 300 ms of its spoken verb, the result holds at least 1.5 seconds, and narration never describes what has not happened or has already gone.
- Demonstrations feel like a skilled presenter working live. The cursor moves purposefully to real controls and the real UI responds, with one emphasis per beat. Static, dashboard, and diagram scenes use a guided cursor, highlight, or progressive trace on the element being named, never an accidental freeze or motion for its own sake.
- Every film has a timestamped cue sheet (narration, screen, cursor or action, resulting state, camera, transition) and a sync check bound to the exact encoded file. Then the whole file is watched and heard. A successful render is not verification, and remaining limitations are reported.
- Local narration and transcription come first for every asset; paid speech is a per-line fallback after a failed review, at the lowest adequate model.

## Provider availability

- Obey `registry/fleet-profile.json` dispatch policy before invoking an agent host, CLI, cloud runner, or API.
- Give every supported host (Cursor included, where the fleet profile marks it active) the same canonical capabilities, MCP ownership, worktree policy, review requirements, and drift enforcement. Use read-only account or local configuration checks for health evidence; do not consume a paid agent run merely to probe availability.

## Cost-aware provider routing

Choose by task fit, total cost, latency, quality and privacy. Reuse accepted outputs first; use adequate local or already-authorized hosted provider routes where suitable. Configured credentials do not establish entitlement or free usage. LLM APIs do not automatically replace speech, music or video. Reserve paid speech providers for their lowest-cost adequate model or a justified quality/capability/speed benefit; once selected, prefer the host-native connector and existing specialist skills. Check workspace, allowance, reset, permissions, model and clone readiness; cap previews and the whole job before spending. Do not change billing, enable overages, upload private recordings or mutate a clone without authority.

Batch independent deferrable work only when the provider supports the required endpoint and discount; do not delay interactive work for batch savings. Keep stable prompt prefixes, use supported cache controls, and measure actual cache reads, writes, latency and billed cost. Cache media by complete request and dictionary/reference versions, retain validation receipts, deduplicate in-flight work, and regenerate only failing segments. Local warm-model reuse saves latency, not provider charges. Poll/recover an existing run before retrying a chargeable POST; preserve privacy and source/final quality gates throughout.

## Handoff

Report the outcome, changed files, validation evidence, branch or commit when applicable, remaining risks, and the next required gate. Silence or a missing automated review is not approval.
