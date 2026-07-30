# Fleet Capability Contracts

## Purpose

This document is the design contract for managing the personal coding-agent
fleet. It separates a reusable capability from the different native ways each
host exposes it. It is not a claim that every installed host is eligible for
provider dispatch.

The canonical owners remain this repository's capability registry, role
definitions, MCP registry, and generated global policy. A host adapter only
translates those sources into a documented host-native format.

## Operating model

| Concern | Canonical owner | Adapter responsibility |
| --- | --- | --- |
| Always-on policy | `standards/global-agent-policy.md` | Generate the smallest supported instruction/rule file. |
| Specialized work | `roles/*/ROLE.md` | Emit native subagent/droid/agent profiles only where supported. |
| Repeatable workflow | capability-owned `SKILL.md` package | Expose an Agent Skills-compatible package or a host-native equivalent. |
| External integration | `registry/mcps.json` | Emit remote HTTP MCP definitions first; use local processes only where no remote contract exists. Record `pluginOwnersByHost` when a host-native plugin is the sole owner for that host, so global synchronization cannot create a duplicate registration. |
| Multi-component package | capability package | Build a native plugin only when the host needs an actual bundle of skills, agents, hooks, or MCP definitions. |
| Language intelligence | language profile and project overlay | Emit a per-project LSP configuration only for hosts and languages that support it. |
| Lifecycle automation | dedicated reviewed hook capability | Emit no hook by default; hooks require their own adapter and validation. |
| Cross-session context | host-local memory policy | Keep memory project-scoped, opt-in, and free of secrets or private evidence. |
| Unattended execution | `profiles/host-autonomy-mappings.json` | Record the exact vendor-supported setting or flag; do not invent a universal `yolo` field. |

## Canonical skill capability owners

| Capability | Owner | Canonical source | Managed skills | Exposure contract |
| --- | --- | --- | --- | --- |
| `portfolio-engineering-ops` | `portfolio` | `capabilities/portfolio-engineering-ops` | `docs-drift`, `portfolio-audit`, `release-readiness`, `repo-onboard`, `verify-and-commit` | `managed-loose-skills` for all 17 registered loose-skill hosts. Cursor's mapping records its retained-disabled configuration only and does not authorize invocation or dispatch. |
| `framer` | `portfolio` | `capabilities/framer` | `framer`, `framer-code-components` | Atomic `managed-loose-skills` distribution for all 17 registered loose-skill hosts. The CLI skill and code-component companion deploy together; resource files are part of drift parity. Cursor remains retained-disabled. |

## External and evidence-pending skill ownership

`registry/skill-ownership.json` governs skills that AgentHub must classify but
must not copy into a repository-owned capability:

- `use-railway` remains vendor-owned by Railway. AgentHub pins the complete
  verified 1.3.6 tree, distributes it only from a matching local vendor tree,
  rejects unknown divergence, and removes the shared `.agents` shadow only
  after every explicit host target verifies.
- `issue-to-pr` and the legal/knowledge skills remain
  `preserve-pending-evidence`. Exact observed copies are warnings, divergent
  copies are failures, and neither state authorizes promotion into AgentHub.
  Their provider, authentication, provenance, data-boundary, and synthetic
  fixture contracts must be approved first.

These classifications replace ambiguous `unowned-*` results; they do not
suppress duplicate exposure or content-drift findings.

## Autonomy meanings

`repo-autonomous` means that the host can work in the checked-out repository,
run normal local tools, use the configured network/MCP tools, and make ordinary
reversible changes without a host prompt. It does **not** authorize production
deployment, credential changes, secret access, destructive cleanup, or external
communication. Those remain governed by the global policy and repository
instructions.

`machine-maintenance` is deliberately not a default. A host may technically
offer a broader bypass switch, but that is only a launch profile for an
explicitly authorized maintenance task.

## Host contract matrix

Legend: **V** = native contract verified from current official documentation or
the installed CLI help; **D** = discovery required before emitting a format;
**N/A** = the host has no comparable surface.

| Host | Rules | Agents / subagents | Skills | Plugin / extension | MCP / ACP | LSP | Hooks | Memory | Headless / strongest unattended contract | Rollout state |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Codex | V | D | V | V | V / V | D | D | D | `approval_policy=never` plus `sandbox_mode=danger-full-access`; the broader dangerous bypass remains task-scoped | Active; retain verified native adapters and complete discovery before emitting agent, hook, LSP, or memory files |
| Claude Code | V | V, plus agent view/teams/workflows/worktrees | V | V | V / N/A | V (code-intelligence plugin) | V | V (project-local) | `bypassPermissions` / `--dangerously-skip-permissions`; `claude -p` for headless | Active; native automation features are registered with explicit experimental and scheduling guards |
| Qwen Code | V | V | V | V (extensions) | V / N/A | V | V | V | `--yolo`; headless and experimental LSP are supported | Active, complete the existing adapter rather than using it as the fleet template |
| OpenCode | V | V | V | V | V / V | V | V | D | `permission: "allow"`; `--auto` for unattended prompts | Active, needs native role and capability adapters |
| Gemini CLI | V | V | V | V | V / V | V | V | V | `--yolo --skip-trust` | Active, needs role/extension contract review |
| Copilot CLI / VS Code | V | V | V | V | V / V | V | V | V | CLI `--allow-all --autopilot --no-ask-user`; VS Code has separate workspace/user policy | Active CLI; Insiders retained, both need the same plugin-capability adapter |
| Devin | V | V | V | V | V / V | N/A | V | D | `--permission-mode dangerous`; config has scoped allow/deny/ask | Retained inactive; ready for native configuration, not an Open VSX-only surface |
| Antigravity CLI / desktop / IDE | V | V | V | V | V / D | D | V | D | `--dangerously-skip-permissions` or documented wildcard permissions | Active; use its native plugin package, do not assume Gemini's schema or transport limits |
| Grok CLI | V | V | V | V | V / V | V | V | V | `--permission-mode bypassPermissions`; headless `grok agent --always-approve` | Active, needs full role/LSP/memory adapter |
| Hermes | V | D | V | V | V / V | D | V | V | No verified universal bypass contract in the managed Windows install | Active; complete discovery before expanding beyond skills/MCP/hooks |
| Warp / Oz | V | D | V | D | V / D | D | D | UI permission profile and per-task run-until-complete controls | Active; retain skill/MCP path, discover native plugin/agent schema before emitting it |
| Cline CLI / ACP / Kanban | V | V (read-only built-in subagents; custom role schema D) | V | V (CLI/SDK/Kanban native plugins only) | V / V | D | D | D | `--auto-approve true` (YOLO equivalent); `--acp` for ACP | Active; native MCP/skills/rules/profile configured, connectors support-only |
| Qoder CLI / Desktop / JetBrains / QoderWork | V | V | V | V | V / V | D | D | D | `--dangerously-skip-permissions` / `bypass_permissions`; `--acp` for ACP | Active; native MCP/settings, skills, plugins, agents, and ACP profile configured |
| Factory Droid | V | V | V | V | V / D | D | D | `droid exec --auto high`; unsafe skip is only for isolated sandboxes | Retained inactive; never make unsafe skip the desktop default |
| Sourcegraph Amp | V | D | V | V | V / D | D | D | Commands are normally non-interactive; headless availability is plan-dependent | Retained inactive; MCP first, plugin only for Amp-native behavior |
| Windsurf / Cascade | D | D | V (observed) | D | V / D | D | D | D | D | Retained inactive; preserve current files and complete official-schema discovery first |
| Cursor / Cursor Agent | V | V | V | V | V / D | D | D | D | Vendor supports unattended modes, but dispatch is owner-held | Retained-disabled: no invocation, probing, or configuration activation |

## Design decisions

1. **Skills are the portable unit.** Use the Agent Skills-style `SKILL.md`
   package as the reusable payload when the host supports it. Do not duplicate
   the skill's source for every host; deploy links/copies only through a
   host-specific adapter.

2. **Plugins are host-specific bundles, not a universal artifact.** Claude,
   Codex, Copilot/VS Code, Devin, Antigravity, Qwen, Grok, Factory, and Amp
   have materially different plugin contracts. Build a plugin only when it
   delivers more than a skill—for example a custom agent, hook, or bundled MCP
   definition. A loose skill is preferred where that is all the host needs.
   MCP placement follows the same ownership rule: a bundled MCP is emitted by
   the plugin on hosts where that plugin is enabled, while a direct global
   fallback may remain for hosts without the bundle. See
   `docs/mcp-ownership-2026-07-24.md` for the current reconciliation.

3. **Roles compile independently from skills.** The common fleet roles are
   scout, implementer, reviewer, and verifier. They must be generated as
   Claude-style agents, OpenCode Markdown agents, Devin `AGENT.md` profiles,
   Qwen agents, Qoder Markdown agents, Grok profiles, Factory droids, or Copilot custom agents only
   where the native contract is verified. A host without a verified role format
   gets the global policy and skills—not a fabricated agent file.

4. **Remote HTTP MCP is the default integration transport.** The canonical
   MCP registry selects direct HTTP endpoints with user-mediated OAuth or
   environment-variable references. Local Node/Python MCP processes are
   retained only when an equivalent remote server is unavailable. ACP is a
   separate editor/client protocol and must not be mistaken for an MCP server.

5. **LSP is a project language profile, never a fleet-wide daemon switch.**
   The Qwen `.lsp.json` work is valid as a TypeScript project overlay, but it
   must not be copied to every host or language. Each profile records the
   language server prerequisite, supported host format, and focused health
   check. Hosts without a verified LSP configuration remain on repository
   typecheck/lint tools.

6. **Hooks stay disabled by default.** Hooks execute local commands with the
   host's permissions and are an instruction-injection/side-effect boundary.
   A hook can be added only as a named capability with a documented event,
   command, input validation, Windows implementation, timeout, and test. It
   must never be smuggled in through a broad plugin synchronization.

7. **Memory is host-local and project-scoped.** The fleet does not sync model
   memory stores. A memory adapter may enable a host's project-memory feature
   only after it excludes credentials, customer data, source bodies, and
   mutable operational claims. Shared truth remains the explicit policy and
   capability repository.

8. **Autonomy is native and auditable.** The fleet profile records the exact
   per-host setting/flag, not a generic boolean. A wrapper must expose the
   host's documented equivalent and must not silently add a more dangerous
   mode than the selected profile.

## Claude Code native contract

Claude Code is a full orchestration host, not a plugin-and-MCP adapter. Its
native model adds these first-class surfaces to the common fleet contract:

- **Parallel work:** isolated subagents, a background agent view, experimental
  agent teams, worktrees, and dynamic workflows. Roles should remain reusable
  subagent definitions; teams and workflow scripts consume those definitions
  rather than becoming a second role registry.
- **Project execution:** project-local auto memory, resumable/forkable
  sessions, code-intelligence plugins, artifacts, channels, and session-scoped
  scheduled tasks.
- **Automation:** `claude -p` is the headless/SDK entry point. For deterministic
  automation use `--bare` and pass the settings, MCP, agent, and plugin inputs
  explicitly instead of inheriting arbitrary machine state.

The rollout deliberately does **not** enable the following globally:

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — teams are experimental, have
  known coordination/resumption limitations, and multiply token use.
- Ultracode or any saved dynamic workflow — workflows are useful for a
  specifically approved large audit or migration, not every normal task.
- Global hooks — hooks can execute commands, HTTP requests, prompts, or
  subagents with host permissions.
- Cross-host memory synchronization — Claude's auto memory is already
  per-repository and shared across worktrees; the fleet control plane stores
  only stable policy and capability pointers.
- Session cron as a durable scheduler — `/loop` and cron tasks expire and only
  run while the session remains alive. Durable schedules require a separately
  authorized scheduler or cloud/desktop task.

## Required implementation sequence

1. Promote this matrix into a machine-readable host contract registry, with
   source URL, contract version, supported surfaces, and `verified` or
   `discovery-required` state for every field.
2. Update `registry/agents.json`, `registry/hosts.json`, and
   `profiles/host-autonomy-mappings.json` from that registry. Remove stale
   claims such as OpenCode being only an agent/MCP host and Devin being only an
   Open VSX/MCP host.
3. Add adapter emitters and validators in this order: OpenCode, Copilot/VS
   Code, Devin, Antigravity, Grok, then the inactive verified hosts. Each
   emitter must be idempotent and must validate the host's native parser or
   CLI before reporting it ready.
4. Add the four common roles only to hosts with a verified native custom-agent
   format. Retain specialized roles as separate capability owners.
5. Move broad host configuration into the adapter emitter. Keep project
   overlays (LSP, repository rules, project MCP) outside user-global state.
6. Add no global hook or cross-host memory synchronization. Implement each
   only after an explicit, separately reviewed capability request.
7. Leave Cursor disabled. Treat Windsurf and any other unverified
   surface as discovery work rather than creating speculative files.

## Validation gates

For each host adapter, validation must prove all of the following without
launching a paid cloud run or revealing credentials:

- generated configuration parses according to the host's native checker or
  a documented schema;
- capability source ownership has no duplicate active copy in the host;
- remote MCP entries use the canonical endpoint and no literal secret;
- host-specific roles, skills, plugin manifests, and LSP overlays load from
  their documented locations;
- the selected repo-autonomous mode is present exactly as recorded;
- discovery-required hosts remain untouched; and
- Cursor's provider hold remains fail-closed.

## Primary references

- [OpenCode rules, agents, permissions, LSP, MCP, ACP, skills, and tools](https://opencode.ai/docs/)
- [Qwen Code configuration and extensibility](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/)
- [Devin CLI extensibility and configuration](https://docs.devin.ai/cli/extensibility/configuration)
- [VS Code agent customization](https://code.visualstudio.com/docs/agents/concepts/customization)
- [Antigravity CLI documentation](https://www.antigravity.google/docs/cli-overview)
- [Factory Droid CLI reference](https://docs.factory.ai/reference/cli-reference)
- [Sourcegraph Amp plugin API](https://ampcode.com/manual/plugin-api)
- [Warp documentation](https://docs.warp.dev/)
- [Claude Code extension model](https://code.claude.com/docs/en/features-overview)
- [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams)
- [Claude Code dynamic workflows](https://code.claude.com/docs/en/workflows)
- [Claude Code memory](https://code.claude.com/docs/en/memory)
- [Claude Code headless/SDK mode](https://code.claude.com/docs/en/headless)
