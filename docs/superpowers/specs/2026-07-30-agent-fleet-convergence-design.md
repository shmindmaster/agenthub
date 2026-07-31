# Agent Fleet Convergence Design

**Date:** 2026-07-30
**Goal:** Make AgentHub-managed coding-agent capabilities, skills, plugins, MCP registrations, worktrees, and local runtime behavior consistent, deduplicated, and maintainable without deleting unique functionality or protected work.

## Baseline

The full live inventory generated on 2026-07-30 reports 61 passes, 22 warnings, and 18 failures. Product Demo Studio 1.0.0 and the managed MCP direct-registration sets pass across all 18 mapped host surfaces. The remaining drift is outside that completed capability:

- Nine skill failures: one duplicate `use-railway` exposure and eight unowned skills with divergent host copies.
- Twenty skill warnings: unowned loose skills repeated across several hosts without a canonical capability owner.
- Eight worktree failures: three registered ABACare worktrees below a temporary Codex workspace and five Grok-created repositories below an unapproved native worktree root.
- One root-path failure: `C:\tmp` is recreated by Codex Desktop's host-owned `node_repl` sandbox runtime.
- One inactive-installation warning: the Windsurf executable is not currently resolved.
- One runtime warning: Grok owns one on-demand `chrome-devtools-mcp` process tree consisting of an `npx` launcher, one MCP worker, and its telemetry watchdog. These are related processes, not three independent server instances.

The baseline evidence is stored outside the repository at:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\reports\fleet-inventory\full-refresh-20260730.json`

## Scope and authority

This is personal capability and machine-configuration work. AgentHub remains the control plane. Client trackers, client documentation, client identities, production systems, and customer data are outside scope.

The work may:

- Read registered agent homes, plugin caches, skill roots, process trees, Git metadata, and registered worktrees.
- Promote only unique, reusable, high-value capabilities into AgentHub.
- Merge useful behavior into an existing AgentHub owner when ownership already exists.
- Quarantine byte-equivalent, superseded, or verified redundant copies before removal.
- Migrate verified worktrees to `C:\wt`.
- Update AgentHub registries, deployers, drift checks, tests, documentation, generated instructions, and managed host configuration.
- Commit verified changes directly to `main` without a pull request.

The work may not:

- Invoke, probe, or enable Cursor or Cursor Agent while the provider hold is active.
- Delete dirty or unique work, unreachable commits, evidence, authentication state, credentials, or unclassified content.
- Invent unsupported host plugin formats or modify undocumented host behavior merely to silence the scanner.
- Kill similarly named Node or Python processes without proving their complete owner process tree.
- Add GitHub Actions workflows. Run the documented repository-native validators locally.
- Create a worktree outside `C:\wt`.

## Architecture

The cleanup has five bounded components.

### 1. Evidence inventory

`scripts\Test-LiveAgentFleetDrift.ps1` remains the authoritative live inventory. It produces structured evidence for every host discovery root, configured MCP set, installed plugin, exposed skill, registered or native worktree, forbidden root path, and relevant process tree.

The inventory must distinguish:

- A duplicated capability from the same host discovering two roots.
- Identical loose copies that lack an AgentHub owner.
- Divergent copies that require behavior comparison.
- Plugin cache generations from active plugin installations.
- One MCP server process tree from multiple independent MCP server instances.
- Clean redundant worktrees from dirty or uniquely committed worktrees.

### 2. Capability ownership resolver

Each unowned or duplicated skill receives one evidence-backed disposition:

- **Retain as canonical:** unique, reusable, high-value behavior becomes one AgentHub capability owner.
- **Merge into owner:** useful behavior is incorporated into an existing capability and the superseded copy is retired.
- **Retain host-native:** the host is the verified owner and AgentHub records rather than duplicates it.
- **Quarantine and retire:** byte-equivalent, obsolete, low-value, or superseded content is moved to managed quarantine and then removed from active discovery roots.
- **Preserve pending evidence:** divergent content whose value or dependency cannot be proven remains untouched and keeps the scan failing.

Canonical promotion requires a registry entry, stable source path, content hash, host mappings, deployment status, tests, and drift enforcement. A skill is not made canonical merely because it exists in several homes.

### 3. Worktree reconciler

Each of the eight noncompliant worktrees is inspected for:

- Current branch and HEAD.
- Dirty and untracked files.
- Ahead, behind, and upstream state.
- Reachability of commits from durable local or remote refs.
- Patch and tree equivalence with retained branches.
- Registered-worktree versus standalone-repository status.

Dirty or unique work is migrated intact to `C:\wt\<repo>\<task>` using the AgentHub worktree policy. Clean redundant work is removed only after its commits and tree are proven recoverable or superseded. Registered worktrees are removed through their owning repository; native standalone repositories are quarantined before deletion. Worktree mutations are serialized.

### 4. Runtime and root-path resolver

The `C:\tmp` and MCP-process findings use the Superpowers systematic-debugging sequence:

1. Reproduce and timestamp creation.
2. Trace the creating process and its ancestors.
3. Identify the configuration and environment boundary that selects the path or launches the server.
4. Compare with a working supported host-native pattern.
5. Form and test one minimal hypothesis.
6. Implement only a supported root-cause fix through AgentHub's managed profile.

Codex's host-owned `node_repl` remains host-owned. If Codex exposes no supported configuration that prevents the root creation while preserving required behavior, the result is an explicit platform blocker rather than an improvised junction, access-control hack, or false pass.

For local MCPs, a launcher, worker, and watchdog in one traced tree count as one on-demand runtime. Independent top-level server trees for the same contract count as duplication. Remediation changes configuration ownership; it does not indiscriminately terminate processes.

### 5. Convergence and verification gate

AgentHub deployers apply the resolved ownership model to mapped hosts. Generated artifacts come only from canonical policy and registry sources. Drift tests fail when an unowned copy, stale plugin generation, unmanaged worktree root, forbidden root path, or duplicated local runtime returns.

Completion requires a fresh whole-fleet scan and independent review. Previous reports cannot establish completion after configuration, source, worktree, or runtime changes.

## Execution model

Superpowers is the execution discipline, not a second capability system.

1. Use `dispatching-parallel-agents` for three independent read-only investigations:
   - Skill ownership and value classification.
   - Worktree preservation and reachability.
   - Runtime, `C:\tmp`, and MCP process ownership.
2. Consolidate their evidence into one implementation plan.
3. Use one temporary AgentHub worktree below `C:\wt` for implementation isolation. No pull request is created.
4. Use `subagent-driven-development` sequentially. One fresh implementer owns one bounded task; concurrent implementers may not write shared configuration.
5. Require test-driven development for deployer, validator, ownership, and path-safety behavior.
6. Require an independent task review after each implementation task and one whole-change review at the end.
7. Fast-forward verified commits to `main`, push `main`, and remove the temporary worktree and branch after reachability verification.

## Failure handling

- A conflicting skill is never overwritten before its unique behavior is recorded and reconciled.
- A dirty worktree is never deleted. Failed migration leaves the source untouched.
- A quarantine operation records source path, reason, hash or Git identity, timestamp, and recovery location.
- A failed host deployment stops that capability's convergence and preserves the last verified copy.
- Unsupported host behavior remains a named blocker and cannot be converted into a pass through a scanner exclusion.
- Three failed fix hypotheses for the same root cause stop implementation and trigger an architectural review.
- Cursor configuration may be synchronized as retained-disabled, but Cursor may not be launched for smoke testing.

## Test and validation strategy

Repository changes follow red-green-refactor:

- Add failing Pester fixtures for each new drift classification or deployment behavior.
- Confirm each test fails for the intended missing behavior.
- Implement the smallest source change.
- Run the focused Pester file and then the complete affected suite.

The final validation set includes:

- `Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1`
- `Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1`
- `Invoke-Pester -Path .\tests\PathSafety.Tests.ps1`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-FullAccessAgentProfile.ps1`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-LiveAgentFleetDrift.ps1 -Json`
- `node .\packages\handoff-plugins\plugins\product-demo-studio\scripts\validate-host-parity.mjs`
- Repository status, branch, worktree, and `origin/main` reachability checks.
- A timed process-tree and CPU-delta sample for local MCP runtimes.
- A fresh-session observation for forbidden root-path recreation.

The GitHub workflow is not run.

## Completion criteria

The fleet is considered consistently configured, deduplicated, and streamlined only when:

- The fresh live inventory reports zero failures.
- No managed host discovers two active copies of the same canonical skill.
- No divergent unowned skill remains in more than one active host discovery root.
- Repeated loose skills have one registered AgentHub owner or an explicit host-native owner.
- Product Demo Studio and MCP direct-registration parity continue to pass for all 18 mapped host surfaces.
- Every surviving user-created worktree resolves below `C:\wt`.
- Every removed worktree or skill has recoverability evidence.
- `C:\tmp` is absent and remains absent during the defined fresh-session observation, or the final result is explicitly blocked by a verified Codex platform limitation.
- Every running local MCP process tree has one identified owning agent and intended on-demand contract.
- No duplicate top-level local MCP server trees exist for the same host and contract.
- Cursor remains retained-disabled.
- Warnings are limited to explicit, reviewed inactive-host or external-platform limitations; no unexplained duplication warning remains.
- All focused and full validation commands pass.
- An independent final reviewer finds no unresolved critical or important issue.
- Verified commits are present on `origin/main`, and the temporary worktree and branch are removed safely.
