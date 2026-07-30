# Live Agent Fleet Drift Remediation Plan

## Classification

Personal capability and machine-configuration work. The AgentHub repository is
the canonical control plane. Live agent homes are deployment/runtime surfaces,
not independent authorities.

## Global Constraints

- Preserve user work, divergent custom content, branches, commits, credentials,
  authentication state, and active runtime state.
- Do not invoke, probe, or route work to Cursor while its provider hold is
  active.
- Do not start coding-agent applications or paid provider sessions as part of
  validation.
- Claude Cowork and other legitimate agent runtimes may auto-start or remain
  running; runtime presence alone is not drift.
- `C:\wt\<repo>\<task>` is the only approved user-created worktree root.
- Do not create new directories directly under `C:\` other than the approved
  `C:\wt` worktree root.
- Back up or quarantine live configuration before mutation. Remove obsolete
  content only after required content and dependencies are verified.
- Never copy credentials or tokens into AgentHub, reports, adapters, or backup
  artifacts.
- Use existing capability ownership from `registry/capabilities.json`,
  `registry/plugins.json`, `registry/skills.json`, and `registry/mcps.json`;
  do not invent new owners or packaging.
- Do not touch unrelated concurrent CI/workflow changes.
- Each task writes a detailed report into the plan-scoped SDD workspace. A
  fresh reviewer verifies the report and current live evidence before the task
  is accepted.

## Task 1: Converge Skill and Plugin Exposure

### Ownership

- Live Claude skill configuration under
  `C:\Users\SaroshHussain\.claude\skills`.
- Live Qoder skills/plugins under `C:\Users\SaroshHussain\.qoder`.
- Live GitHub Copilot skills/plugins under
  `C:\Users\SaroshHussain\.copilot`.
- No AgentHub repository files unless the controller explicitly expands the
  task after review.

### Requirements

1. Remove the retired `agent-fleet-ops` Claude skill from active discovery,
   preserving a recoverable backup outside active discovery.
2. Converge Qoder's duplicated Product Demo Studio and Product Experience
   Engineering exposures on the registered plugin-owned surfaces. Preserve
   any divergent loose content before taking it out of active discovery.
3. Converge Copilot's nine Vercel duplicate skill IDs on one registered
   exposure path. Preserve any divergent loose content before taking it out
   of active discovery.
4. Do not change shared `.agents` skills or affect unrelated agents.
5. Run the live inventory checker and include before/after evidence for Claude,
   Qoder, and Copilot in the task report.

### Acceptance Criteria

- Claude has no active `agent-fleet-ops` discovery path.
- Qoder has no duplicate configured skill IDs and no canonical mismatch for
  `product-demo-studio-visual-assets`.
- Copilot has no duplicate configured skill IDs for the Vercel set.
- Required skill/plugin content remains available through the registered owner.
- Backups are outside every registered discovery root.

## Task 2: Converge MCP and Root-Runtime Configuration

### Ownership

- Live Codex MCP/connector configuration under
  `C:\Users\SaroshHussain\.codex`.
- Live Grok MCP configuration under `C:\Users\SaroshHussain\.grok`.
- User and process environment variables relevant to temporary paths.
- Investigation of the recreation of `C:\tmp`.
- No AgentHub repository files unless the controller explicitly expands the
  task after review.

### Requirements

1. Reconcile Context7, Exa, and Tavily so Codex does not expose each capability
   simultaneously through a direct MCP definition and an installed connector
   package. Keep the registered, currently supported exposure and preserve
   authentication/configuration references.
2. Remove or register Grok's extra `n8n` MCP only according to existing
   AgentHub ownership. Do not invent ownership.
3. Identify the executable and launch/configuration path that recreates
   `C:\tmp`. Correct any controllable environment or configuration that writes
   there. If the currently running Codex build hard-codes the path, record the
   exact limitation and the restart/update gate; do not conceal it by deleting
   the directory while the process can recreate it.
4. Do not invoke MCP servers or start coding-agent applications. Read-only
   parsing and process-tree inspection are allowed.
5. Run the live inventory checker and include before/after evidence for Codex,
   Grok, MCP duplication, prohibited root paths, and local MCP workers.

### Acceptance Criteria

- Codex has one configured exposure for each owned MCP/connector capability.
- Grok has no unregistered MCP definition.
- No controllable configuration points temporary output at `C:\tmp`.
- `C:\tmp` is removed only if it is safe and cannot be recreated by currently
  running processes; otherwise the task report states the exact remaining
  external gate.
- No local MCP workers are left running by validation.

## Task 3: Repair Devin State and Preserve Noncompliant Worktrees

### Ownership

- Live Devin plugin lock/cache under `C:\Users\SaroshHussain\.devin`.
- Missing Devin source references under
  `C:\Users\SaroshHussain\sh-portfolio-devin\plugins`.
- Registered and standalone worktrees outside `C:\wt`.
- No AgentHub repository files unless the controller explicitly expands the
  task after review.

### Requirements

1. Reconcile Devin's five lock entries whose local sources were deleted and
   whose cache entries are dangling reparse points. Preserve enough metadata
   to recover, and converge only to existing registered plugin ownership.
2. Inventory every noncompliant worktree's repository, branch, upstream,
   dirty files, commits ahead/behind, and untracked files.
3. Preserve dirty work and ahead commits before any relocation. Use Git
   bundles, patches, or explicit file manifests as appropriate without
   embedding credentials.
4. Relocate only when the destination under `C:\wt` can be created and verified
   without losing work. Do not remove a source worktree/clone until the
   controller and reviewer can verify the preservation evidence.
5. Do not invoke any agent provider or native host worktree isolation feature.
6. Run the live inventory checker and include before/after evidence for Devin
   and worktree drift.

### Acceptance Criteria

- Devin has no dangling plugin source/cache reference, or the report identifies
  a precise unsupported-format blocker with preserved recovery metadata.
- Every noncompliant worktree has a preservation manifest.
- Any relocated worktree is under `C:\wt` and reproduces its source branch,
  worktree state, untracked files, and ahead commits.
- No source worktree or clone containing unverified work is deleted.

## Task 4: Integrate, Validate, and Report the Fleet

### Ownership

- Controller-owned AgentHub inventory/checker, registries, tests, and
  documentation already changed for this remediation.
- Final live validation and task-review integration.

### Requirements

1. Review each task report with a fresh reviewer and return Important or
   Critical findings to its implementer.
2. Integrate only reviewed remediation results.
3. Run focused Pester coverage, the normal AgentHub validation, and the
   comprehensive live-fleet gate.
4. Reconcile the live drift report with actual post-remediation evidence.
5. Distinguish resolved drift, preserved-but-pending worktrees, external
   product limitations, inactive-host warnings, and unrelated concurrent test
   failures.

### Acceptance Criteria

- All safely controllable configuration drift is resolved and verified.
- Remaining failures, if any, each name an exact external or preservation gate;
  none are reported as resolved.
- No prohibited root directory was newly created by the remediation.
- The final report lists changed live paths, backups, validation evidence, and
  remaining risks.

## Task 6: Retire or Canonicalize Remaining Loose Capabilities

### Ownership

- Repeated or content-divergent loose skill/plugin surfaces reported by the
  comprehensive live checker after Tasks 1-3.
- Relevant canonical AgentHub capability/plugin/skill registries and packages.
- No provider invocation and no Cursor mutation while its hold remains active.

### Requirements

1. Re-inventory every remaining repeated or divergent loose capability by
   exact skill ID, host, path, content hash, registered owner, and active
   discovery semantics.
2. Default to removal from active host discovery when a capability is stale,
   duplicated, unowned, broken, or low-value. Preserve a recoverable copy
   outside discovery before removal.
3. Retain only a capability that is both unique and demonstrably high-value.
   Before retaining it, establish one canonical AgentHub owner/source, validate
   its package/manifest, register supported host exposures, then redeploy from
   AgentHub. Do not keep a host-local copy as an informal authority.
4. Do not centralize credentials, client content, private evidence, indexes,
   model data, generated caches, or vendor build inputs that are not runtime
   capabilities.
5. Byte-equivalent repeated copies do not justify retention. Content
   divergence requires inspection for unique high-value behavior; ordinary
   wording/version drift is not sufficient.
6. Respect inactive/held hosts: clean their deployable configuration/files
   without invoking them; retain a warning only where safe mutation is
   unsupported or the hold prohibits it.
7. Run the comprehensive live checker and record each retained, retired,
   canonicalized, and externally blocked ID.

### Acceptance Criteria

- No remaining active loose capability has an unknown owner.
- No configured host exposes the same skill ID through two runtime surfaces.
- Every retained capability is unique, high-value, canonical in AgentHub, and
  deployed from that source.
- All removed content is recoverable outside registered discovery roots until
  final review.
- Remaining warnings are explicit unsupported/held-host gates, not untreated
  duplication.

## Task 5: Reconcile Pull Requests and Superseded Branches

### Ownership

- GitHub pull requests #9, #10, and #13 in `shmindmaster/agenthub`.
- Their remote head branches and corresponding local worktrees/branches.
- No unrelated pull request or branch.

### Requirements

1. Refresh `main` and inspect each pull request's exact base/head SHA, commit
   set, changed files, reviews, unresolved threads, checks, mergeability, and
   relationship to the other pull requests.
2. Identify unique work that is not already on `main`; do not infer
   supersession from branch age, behind/ahead counts, or PR title alone.
3. Rebase or update a branch only when its unique work is still required and
   the update can be reviewed without overwriting protected WIP.
4. Merge only a reviewed pull request whose exact head is ready and whose
   changes remain required. A missing check suite is not a passing check.
5. Close and delete a superseded remote branch only after proving its required
   commits or equivalent changes are on `main` or another retained branch.
6. Preserve any dirty linked worktree or unpushed local commit. Remove a
   worktree only through the repository worktree policy.
7. Use the authenticated `shmindmaster` account and the `gh` CLI for GitHub
   operations.

### Acceptance Criteria

- Each of PRs #9, #10, and #13 has an evidence-backed disposition: merge,
  retain/update, or close as superseded.
- No unique required commit or dirty local work is lost.
- Merged or superseded remote branches are deleted only after verification.
- Local branch/worktree cleanup distinguishes completed remote work from
  protected in-progress state.
- Final evidence records the exact head SHA and GitHub state used for each
  action.
