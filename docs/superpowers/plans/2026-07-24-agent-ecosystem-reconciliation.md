# Agent Ecosystem Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the personal coding-agent ecosystem back to a validated, evidence-backed, internally consistent state across registries, packages, adapters, local managed host settings, and documentation.

**Architecture:** Registry JSON remains canonical inventory; capability package trees remain canonical implementation sources; host adapters emit only documented native formats. Repairs are narrow and idempotent, with external host settings changed only by the existing managed profile script or the central MCP synchronizer.

**Tech Stack:** PowerShell 5.1/7, Pester, JSON/TOML, Markdown Agent Skills, native plugin manifests, Git, official host documentation.

## Global Constraints

- Preserve the existing dirty worktree and unrelated WIP.
- Do not invoke, probe, enable, or configure Cursor dispatch while the provider hold is active.
- Do not store credentials, OAuth state, cookies, tokens, or private evidence.
- Do not delete unregistered packages in this pass; classify them and record the result.
- Do not rewrite unrelated host settings or run paid/cloud/production operations.

---

### Task 1: Prove the package-version drift with a failing regression test

**Files:**
- Modify: `tests/Apply-FullAccessAgentProfile.Tests.ps1`

**Interfaces:**
- Consumes: `New-DistributionFixture`, `Invoke-DistributionOnly`.
- Produces: A test fixture whose canonical Product Experience Engineering version is `1.1.0`, proving the distribution script must read the manifest version instead of hard-coding `1.0.0`.

- [x] Change the fixture manifest and native plugin-cache versions from `1.0.0` to `1.1.0`.
- [x] Run `pwsh -NoProfile -File .\tests\Apply-FullAccessAgentProfile.Tests.ps1`.
- [x] Confirm the test failed specifically because the script rejected `1.1.0` as an unexpected Product Experience Engineering version.

### Task 2: Repair version handling and managed Claude policy

**Files:**
- Modify: `scripts/Apply-FullAccessAgentProfile.ps1`
- Modify: `tests/Validate-AgentEcosystem.ps1`
- Modify: `tests/Apply-FullAccessAgentProfile.Tests.ps1`

**Interfaces:**
- Consumes: The canonical manifest version and the Claude settings JSON object.
- Produces: Version-independent distribution validation and managed Claude policy enforcement.

- [x] Remove the hard-coded Product Experience Engineering version check; retain the manifest as the source of the expected version.
- [x] In the managed Claude settings block, set `cleanupPeriodDays = 7`.
- [x] Remove `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from the managed Claude `env` map instead of disabling unrelated settings.
- [x] Extend ecosystem validation to fail when Claude retention is not 7 or when the experimental agent-team flag is set to `1`.
- [x] Run the focused distribution and validator commands; confirm the version regression is green and the live validator now reports the Claude policy checks as pass.

### Task 3: Reconcile canonical capability hashes and registry terminology

**Files:**
- Modify: `registry/capabilities.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: Current canonical package trees and the registry capability list.
- Produces: Current content hashes and documentation that accurately names nine canonical capabilities.

- [x] Replace the three drifted hashes with the current SHA-256 tree values for `product-demo-studio`, `product-experience-engineering`, and `browser-toolkit`.
- [x] Update the README from “seven deployable plugins” to the actual capability breakdown: seven plugin capabilities, one skill+MCP capability, and one skills+MCP+adapters capability.
- [x] Use registry IDs consistently in the README while retaining human-readable aliases only where useful.
- [x] Run `pwsh -NoProfile -File .\tests\Validate-AgentEcosystem.ps1 -IncludeGlobalInstructions` and confirm all hash checks pass.

### Task 4: Validate and classify noncanonical packages and host surfaces

**Files:**
- Create: `docs/agent-ecosystem-classification-2026-07-24.md`
- Modify: `registry/capabilities.json` only if an evidence-backed package promotion is required

**Interfaces:**
- Consumes: Package manifests, skills, ownership metadata, Git history, adapter paths, and registry mappings.
- Produces: An explicit classification for `ediscovery-processing`, `knowledge-system`, and `notebooklm-ops`, plus host states for inactive/discovery-required surfaces.

- [x] Verify every package manifest parses and record its host formats and skill count.
- [x] Search Git history and repository references for an owner and active consumer before proposing any registry promotion.
- [x] Classify each package as canonical, retained inactive, or deletion candidate; leave deletion candidates untouched pending separate authorization.
- [x] Record that Cursor remains retained-disabled, while Amp, Devin, Factory, VS Code Insiders, and Windsurf remain inactive/retained according to registry state.
- [x] Record OAuth-pending and discovery-required MCP/host gates separately from local validation results.

### Task 5: Reconcile managed adapters and generated artifacts

**Files:**
- Modify only source or generated files shown to drift by the adapter audit
- Potentially modify: `registry/adapter-status.json`, `registry/hosts.json`, `registry/host-capability-contracts.json`, `registry/installations.json`, `registry/role-mappings.json`

**Interfaces:**
- Consumes: Canonical registries, documented host contracts, package manifests, and generated instruction templates.
- Produces: Idempotent adapters with no duplicate canonical skill owners and no speculative discovery-required formats.

- [x] Run the repository’s read-only inventory and adapter drift checks.
- [x] Validate Qwen subagents and project-scoped `.lsp.json` behavior without copying LSP settings fleet-wide.
- [x] Validate plugin manifests against Claude/Codex/VS Code/Qwen formats where supported.
- [x] Reconcile only evidence-backed host metadata and regenerate managed instruction files through the repository’s generator.
- [x] Do not invoke Cursor or write activation state for Cursor.
- [x] Bound generic skill distribution to explicit host mappings, preserve expected junctions, and quarantine exact canonical duplicates from unmapped/native surfaces.
- [x] Remove the verified duplicate Windsurf `devin/context7` alias while preserving unknown MCP servers.

### Task 6: Reconcile MCP configuration without credentials

**Files:**
- Modify only MCP adapter or registry files proven to drift

**Interfaces:**
- Consumes: `registry/mcps.json`, host registrations, and documented host-specific MCP schemas.
- Produces: Canonical endpoints, correct transports/placeholders, no literal secrets, and explicit auth-pending states.

- [x] Run `pwsh -NoProfile -File .\scripts\Test-McpConfig.ps1`.
- [x] Run `pwsh -NoProfile -File .\scripts\Test-McpSecrets.ps1`.
- [x] Apply MCP synchronization only through `Sync-AgentCapabilities.ps1`; no credentials were written.
- [x] Confirm OAuth-pending servers remain pending and no credentials are written.

### Task 7: Full verification and handoff

**Files:**
- No source changes unless verification exposes a new root cause

**Interfaces:**
- Consumes: All repaired registry, package, adapter, and local-policy state.
- Produces: Evidence-backed status by gate and a list of remaining external/discovery/authorization blockers.

- [x] Run `pwsh -NoProfile -File .\tests\Apply-FullAccessAgentProfile.Tests.ps1`.
- [x] Run `pwsh -NoProfile -File .\tests\Sync-AgentCapabilities.Tests.ps1`.
- [x] Run `pwsh -NoProfile -File .\tests\QwenSubagents.Tests.ps1`.
- [x] Run `pwsh -NoProfile -File .\scripts\Verify-PluginPackages.ps1`.
- [x] Run `pwsh -NoProfile -File .\tests\Test-HostReadiness.ps1`.
- [x] Run `pwsh -NoProfile -File .\tests\Validate-AgentEcosystem.ps1 -IncludeGlobalInstructions`.
- [x] Review `git diff --check`, `git status`, and the final diff for protected WIP or accidental credential material.
- [x] Report repaired, verified, configured, OAuth-pending, discovery-required, inactive, and intentionally retained states separately.
