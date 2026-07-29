# AgentHub Runtime Centralization and Root Cleanup

## Context

The canonical personal capability repository is `C:\Repos\shmindmaster\agenthub`. Historical references to `C:\Repos\agent-capabilities`, `sh-knowledge`, or other retired capability names are migration evidence only. Current registries, installed clients, MCP servers, plugins, and skills are the implementation authority.

This is personal capability work. Use synthetic fixtures only. Do not invoke Cursor while its provider hold is active. Preserve uncommitted work, active worktrees, credentials, private data, and unrelated processes.

## Global Constraints

- Do not create or retain new top-level directories or files directly under `C:\`.
- The repository owns durable source, policy, adapters, registries, tests, and documentation.
- User-scoped runtime state belongs under `%LOCALAPPDATA%\AgentHub\runtime`; cache state belongs under `D:\AI-Platform\cache`; Codex-managed worktrees belong under `$CODEX_HOME\worktrees`.
- Every capability has one canonical owner. Prefer native plugin or connector ownership over generated duplicates; use shared MCP/API ownership only where a native exposure is unavailable.
- `repocontext` is the current knowledge capability. Retired aliases must not be regenerated.
- `agent-fleet-ops` is retired and must not be regenerated.
- Root cleanup is inspect-first. Registered or dirty worktrees must be moved or retained safely, never recursively deleted.
- Tests must prove unsafe drive-root paths fail before any filesystem write.
- Do not print, copy, or commit secret values.

## Task 1: Root-path safeguards and approved locations

Write failing Pester tests first, observe the failures, then implement the minimal safeguards.

- Add a reusable path-safety function that rejects a drive root, empty path, and any unapproved top-level `C:\` target before writes.
- Make `Apply-FullAccessAgentProfile.ps1` synthetic fixtures use an explicit test directory and prevent `$TestDrive` or path-resolution drift from resolving to `C:\`.
- Update Pester tests to syntax supported by the repository's pinned Pester version and pin CI to an exact compatible version.
- Update the worktree policy to make `$CODEX_HOME\worktrees` the Codex-native location and `C:\Repos\_worktrees\<owner>\<repo>\<task>` the manual fallback. Remove `C:\wt` as an approved location.
- Add validation for the forbidden root paths and retired `agent-fleet-ops` skill.
- Do not touch the protected uncommitted `local-ai-stack` work in the original checkout.

## Task 2: Current capability ownership, gateway profiles, and native connectors

Write schema/validation tests first.

- Inventory from the current `registry/capabilities.json`, `registry/mcps.json`, installed plugin state, and current host mappings; do not resurrect historical server or plugin names.
- Add a declarative native-connector matrix identifying plugin-owned, native-connector, shared-gateway, local-only, and provider-held exposure for each current host.
- Add shared gateway profiles for the current MCP registry with least-privilege host mappings and a single loopback streaming HTTP endpoint where the selected gateway supports it.
- Update `Sync-AgentHub.ps1` so native/plugin-owned capabilities suppress duplicate direct MCP entries and gateway-managed tools are generated as one endpoint.
- Preserve local-only servers where a shared HTTP gateway cannot safely own them.
- Keep Cursor configurations retained but never launch or probe Cursor.

## Task 3: Live runtime and filesystem migration

Perform fresh read-only dependency/process checks before each mutation.

- Move pnpm's global store from `C:\cache\pnpm` to `D:\AI-Platform\cache\pnpm`, rehydrate required dependencies, and verify no active process depends on the old store.
- Configure Playwright MCP output under `%LOCALAPPDATA%\AgentHub\runtime\playwright`.
- Audit every registered and unregistered checkout under `C:\wt`; move protected worktrees to approved locations and remove only clean, redundant worktrees with no unique work.
- Remove the retired user skill `C:\Users\SaroshHussain\.agents\skills\agent-fleet-ops`.
- Review root-level temporary artifacts, preserve only required evidence outside the repository, then remove the explicitly listed obsolete root paths.
- Remove plaintext package credentials and user-level token residue without printing values; record any external revocation gate that cannot be completed non-interactively.
- Restart only traced, affected MCP/runtime process trees. Do not terminate unrelated Node, Python, Docker, ComfyUI, or agent-host processes.

## Task 4: Verification, non-recreation, and handoff

- Run focused tests, the full AgentHub validation suite, secret checks, JSON/TOML parsing, and host-readiness checks.
- Under representative client load, verify MCP tool discovery and calls, process counts, root-path non-recreation, and absence of dependencies on old paths.
- Confirm whether Docker MCP Gateway satisfies the required single-endpoint and profile behavior. Use Obot only if the functional proof fails; do not install a fallback speculatively.
- Produce an evidence report with creator attribution, migrations, before/after counts, deleted paths, retained protected work, limitations, and remaining external gates.
- Request independent code review, fix load-bearing findings, and commit the verified repository changes.
