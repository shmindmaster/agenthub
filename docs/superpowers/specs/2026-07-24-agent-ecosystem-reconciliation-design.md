# Agent Ecosystem Reconciliation Design

**Date:** 2026-07-24
**Goal:** Validate, research, repair, reconcile, standardize, and streamline the personal coding-agent ecosystem without enabling held providers, deleting uncertain work, or persisting credentials.

## Scope

The work covers the repository's canonical registries, capability packages, skills, plugin manifests, host adapters, generated instructions, MCP definitions, role mappings, local host configuration writers, and repository-native validation. It includes local machine configuration that is explicitly managed by this repository, but not OAuth approval, credential rotation, cloud-agent runs, production systems, external communication, or Cursor activation.

## Design

`registry/*.json` remains the canonical inventory. Capability package contents remain the implementation source. Host adapters translate canonical capabilities into documented native formats; they must not invent formats for discovery-required surfaces. Generated files are outputs of the repository's generators and are reconciled only after their source contracts are validated. Skill distribution is mapping-bounded: a host receives a loose skill only when its capability mapping explicitly owns that surface, while native plugins and expected junctions remain the sole owner on their hosts.

The reconciliation flow is:

1. Capture the existing dirty worktree and preserve all unrelated WIP.
2. Run baseline validators and classify each failure as registry drift, package drift, host-contract drift, generated-file drift, or environment-only drift.
3. Compare host claims against current official documentation or installed CLI help. Downgrade unsupported claims to `discovery-required`; do not emit speculative adapters.
4. Repair the smallest evidence-backed source files: hashes, stale counts/names, registry mappings, adapter emitters, generated instructions, and managed local settings.
5. Classify unregistered packages as canonical candidate, retained inactive, or deletion candidate. No package is deleted in this pass solely because it is absent from the registry.
6. Re-run focused tests, package checks, MCP checks, generated-file checks, and the full ecosystem validator.

## Safety boundaries

- Cursor and Cursor Agent remain retained-disabled. No executable probe, paid run, activation, or dispatch is permitted.
- OAuth and environment-backed secrets remain references only. No tokens, cookies, credentials, or private source bodies enter the repository.
- Legacy packages remain untouched unless a non-destructive repair is clearly evidenced. Removal requires separate explicit authorization after ownership classification.
- Local host settings may be repaired only through the repository's managed writers or a narrowly scoped equivalent, with no unrelated settings rewritten.
- Existing dirty changes are user-owned unless proven otherwise. No reset, checkout, recursive delete, or broad cleanup is allowed.

## Expected repair classes

- Recompute capability hashes after the current WIP settles.
- Align Claude retention with the repository's seven-day worktree policy and remove the globally enabled experimental agent-team flag if it conflicts with the canonical policy.
- Reconcile README and registry terminology/counts.
- Validate plugin manifests and component paths against host-native schemas.
- Validate Qwen extension/subagent/LSP behavior without promoting project LSP configuration to a fleet-wide setting.
- Keep verified MCP transports canonical and mark unsupported host transports as discovery-required.
- Standardize generated instructions and adapter status without duplicating canonical skills.
- Quarantine exact canonical skill trees found on unmapped/native hosts, preserve ambiguous local trees, and retire only explicitly named canonical skill aliases.

## Success criteria

- All repository-native validation commands pass, or every remaining failure is explicitly documented as an external/authentication/discovery gate.
- Every canonical capability has a valid source and current content hash.
- No registry mapping references an unknown host or capability.
- Plugin, skill, agent, MCP, and LSP files parse in their supported host contracts.
- Cursor remains fail-closed and no secret values are exposed.
- Legacy packages have an evidence-backed classification and are not silently removed.
- The final report distinguishes repaired, verified, configured, OAuth-pending, discovery-required, and intentionally inactive states.
