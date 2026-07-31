# Coding-agent plugin, skill, MCP, and subagent matrix

Status date: 2026-07-30
Scope: installed or retained AgentHub hosts on this workstation
Authority: official host documentation plus read-only inspection of the installed CLI/configuration

This matrix records the host-native facts used by AgentHub adapters. A skill being visible is
not proof that a plugin's agents, MCP servers, hooks, permissions, or isolation are active.
Product Demo Studio release eligibility additionally requires host-recorded read-only execution
evidence and a live deployment report; static packaging never satisfies that gate.

Claude and Codex user-installed extra plugins are host-private extensions, not fleet
capabilities. They are preserved in place and excluded from parity, deployment, and
cross-host copying unless they conflict with a canonical AgentHub identity or registration.
Their runtime processes contribute only to aggregate resource observations.

| Host or surface | Official reusable package | Skills | MCP lifecycle | Native subagents | Product Demo Studio deployment and limit |
|---|---|---|---|---|---|
| Codex CLI/Desktop | `.codex-plugin/plugin.json`; documented plugin components do not include `agents/` | Plugin and standalone | Remote plugin MCP is a connection to the hosted service | `~/.codex/agents/*.toml`; per-agent `sandbox_mode` | Plugin supplies skills/MCP; AgentHub separately generates 13 TOML roles and gives six `read-only` sandboxes. ChatGPT Work publication is not proven by the local install. |
| Claude Code | `.claude-plugin/plugin.json` with auto-discovered skills, agents, hooks, and `.mcp.json` | Plugin and standalone | Plugin MCP connects when the plugin/session loads | Plugin or standalone Markdown agents; plugin agents do not honor every standalone permission field | Native package. Six review/arbiter/final roles are shell-free and record plain execution receipts. |
| VS Code Insiders / Copilot agent plugins | Claude-compatible agent plugin registered by `chat.pluginLocations` | Plugin and standalone | Enabled plugin MCP starts automatically and stops when disabled | Plugin agents and coordinator/subagent delegation | Native local package. Windows local-MCP sandboxing must be recorded by the execution receipt. |
| GitHub Copilot CLI | Plugin loaded with `--plugin-dir` | Plugin and standalone | Product Demo Studio strips plugin MCP and uses the shared remote Descript entry | Plugin `agents/*.md` are discovered | Deployed adapter contains all 13 agents and eight skills; the former `skills-only` registry claim was wrong. Per-agent filesystem read-only isolation still needs an external boundary. |
| Cursor IDE/CLI | `.cursor-plugin/plugin.json` | Plugin and standalone | Plugin or global MCP; disabled servers do not load | Plugin/custom agents support `readonly: true` | Active native local Product Demo Studio and Product Experience Engineering plugins, centrally managed global skills/MCP, generated agents, and unrestricted launch policy. The global adapter emits only Cursor's strict remote fields and `cursor-agent mcp list` verifies parsing without a paid model prompt. |
| Factory Droid | `.factory-plugin/plugin.json`; Claude plugin layouts are translated on cache copy | Plugin and standalone | Plugin/global MCP; local command entries create child processes | `droids/*.md` with explicit tools | Install the existing Claude-compatible package. Historical `interactionMode`, `autonomyLevel`, and `autonomyMode` settings were invalid and are retired; autonomy uses `droid exec --auto high`. |
| Qwen Code | `qwen-extension.json` | Extension and standalone | Extension/global remote or stdio; global config wins on name collision | Extension `agents/` or standalone agents | Generated extension now exposes skills plus all 13 agents. Parent `--yolo` can override subagent approval mode, so it is not release-eligible without an external isolated review launch. |
| OpenCode CLI/Desktop | No declarative all-component bundle; JS/TS plugins plus separate skills/agents config | Standalone | Global MCP starts with the host; Desktop shares CLI config | Markdown agents with per-agent `edit`, `bash`, `task`, and MCP permissions | Loose skills plus 13 generated Markdown roles. Six roles deny edits, shell, and further delegation. |
| Gemini CLI | `gemini-extension.json` | Extension and standalone | Extension/global MCP; stdio is a persistent child, remote is a shared service connection | Preview extension or standalone Markdown agents with explicit tools and policy rules | Loose skills plus an AgentHub-managed extension containing 13 roles. Six roles expose only read/search tools and record plain execution receipts. |
| Antigravity CLI | `~/.gemini/antigravity-cli/plugins/<name>/plugin.json` | Plugin and standalone | Current shared path is `~/.gemini/config/mcp_config.json` | Plugin/global Markdown agents with explicit tools and command policy | Managed CLI plugin contains 13 roles; six set `commandExecutionPolicy: off`. Desktop/IDE use the separate `~/.gemini/config` surface. |
| Grok CLI | Claude-compatible plugins and Grok marketplaces | Plugin and standalone | Plugin/global MCP | Native subagents, hooks, sandbox, and worktree features | Native Claude-compatible Product Demo Studio package. Installed Windows read-only sandbox enforcement remains unverified. |
| Qoder CLI | `.qoder-plugin/plugin.json`; installed CLI also translates compatible Claude packages | Plugin and standalone | Plugin/global MCP | Plugin `agents/*.md` with tool allowlists | Native plugin reports all eight skills and 13 agents. CLI `1.1.5` and Desktop `1.106.3` are separate versions/surfaces. |
| Devin CLI/Desktop | `.devin-plugin/plugin.json` | Plugin and standalone | Plugin/global MCP | Custom agents, hooks, sandbox, and ACP | Canonical native manifest exists; retained inactive until install/smoke. Cloud Devin is a separate VM/repository-scoped surface. |
| Cline CLI/SDK/Kanban and IDEs | Native plugins only in CLI/SDK/Kanban; not VS Code or JetBrains | Global `~/.cline` skills across surfaces | Global MCP; local stdio is per host process | Current experimental subagent is fixed, read-only, and cannot edit, browse, use MCP/web, or nest | Loose skills are portable. The fixed reviewer can help with research, but writable generation and MCP/browser-dependent Product Demo Studio roles are not parity-capable. |
| Amp | TypeScript/Bun plugin API plus skills | Standalone | Skill MCP starts with Amp but tools stay hidden until skill activation | Write-capable subagents; custom agent construction is experimental | Loose skills only. A full native policy adapter is not yet verified, so runtime parity remains blocked. |
| Hermes | `plugin.yaml` plus Python plugin | Plugin and standalone | Plugin/global MCP | Delegation/subagents | Loose skills only. Hook errors are logged and execution continues, so hooks cannot be the fail-closed release boundary. |
| Warp / Oz | No documented general plugin bundle; skills, MCP, profiles, environments, and orchestration are separate | Standalone | Configured MCP per Warp/Oz surface | Oz/cloud orchestration rather than portable custom-agent packages | Loose skills only. “Run until completion” can bypass profile deny lists, and native worktrees do not honor `C:\wt`; not release-eligible. |
| Windsurf / Cascade | No documented general user plugin bundle | Standalone | Global MCP | Cascade parallel-agent surfaces, workflows, and worktrees | Dormant supported adapter; no executable is expected on this machine. Loose configuration remains for future reactivation, but runtime readiness is not claimed. |

## MCP process and memory behavior

- Remote HTTP MCP entries such as Context7 and Descript do not create a Node or Python worker
  per agent. Each host opens its own client connection to the same hosted service.
- A canonical local stdio MCP command is a child process owned by the host/session that launched it.
  Seven concurrently open hosts can therefore create seven local workers. AgentHub suppresses
  ordinary globally persisted on-demand local MCPs. Chrome DevTools MCP is the explicit
  user-requested exception: it is configured directly on every supported host using the upstream
  README form, with documented Codex-on-Windows and Antigravity variants. The server launches
  Chrome only when a tool first requires it, but the host may start its local stdio worker sooner.
- Claude and Codex host-private plugins may start additional host-owned workers. AgentHub does
  not classify those workers as canonical fleet duplication, deploy them elsewhere, or terminate
  them; only canonical identity conflicts and aggregate resource limits remain in scope.
- Plugin MCP lifecycle is host-specific: some hosts connect when the plugin/session loads;
  some defer tool schemas; Amp can hide skill tools until activation; VS Code starts enabled
  plugin MCP automatically.
- The Docker MCP gateway remains a partial proof of concept with generation disabled. It must
  not replace direct remote connections until authentication, profile coverage, duplicate
  suppression, health, and ownership are proven.

## Primary official sources

- [OpenAI plugins](https://developers.openai.com/plugins/build/plugins) and [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Claude plugins](https://code.claude.com/docs/en/plugins-reference) and [subagents](https://code.claude.com/docs/en/sub-agents)
- [VS Code agent plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins)
- [Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [Cursor plugins](https://cursor.com/docs/plugins.md) and [subagents](https://cursor.com/docs/subagents.md)
- [Factory plugins](https://docs.factory.ai/harness/plugins)
- [Qwen extensions](https://qwenlm.github.io/qwen-code-docs/en/users/extension/introduction/) and [subagents](https://qwenlm.github.io/qwen-code-docs/en/users/features/sub-agents/)
- [OpenCode agents](https://opencode.ai/docs/agents/)
- [Gemini extensions](https://geminicli.com/docs/extensions/reference/) and [subagents](https://geminicli.com/docs/core/subagents/)
- [Antigravity plugins](https://antigravity.google/docs/cli/plugins) and [subagents](https://antigravity.google/docs/subagents)
- [Grok plugins](https://docs.x.ai/build/features/skills-plugins-marketplaces) and [subagents](https://docs.x.ai/build/features/subagents)
- [Qoder CLI plugins](https://docs.qoder.com/cli/sdk/plugins)
- [Devin plugins](https://docs.devin.ai/cli/extensibility/plugins/overview) and [subagents](https://docs.devin.ai/cli/subagents)
- [Cline plugins](https://docs.cline.bot/customization/plugins) and [subagents](https://docs.cline.bot/features/subagents)
- [Amp plugin API](https://ampcode.com/manual/plugin-api)
- [Hermes plugins](https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins) and [delegation](https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation)
- [Warp skills](https://docs.warp.dev/agent-platform/capabilities/skills) and [MCP](https://docs.warp.dev/agent-platform/capabilities/mcp)
- [Windsurf skills](https://docs.windsurf.com/windsurf/cascade/skills), [hooks](https://docs.windsurf.com/windsurf/cascade/hooks), and [worktrees](https://docs.windsurf.com/windsurf/cascade/worktrees)
