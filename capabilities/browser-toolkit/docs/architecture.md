# Architecture and agent comparison

Chrome DevTools MCP is selected as the fleet-wide live-browser diagnostics layer
because it can launch or attach to a visible Chrome profile and
provide DOM/accessibility, console, network, Lighthouse, and performance
evidence. Chrome experimental features are off.

Repository-owned Playwright remains the deterministic regression and master
capture layer when already present. This toolkit does not install Playwright or
Playwright MCP. Hermes native browser remains the lightweight browsing layer;
it does not replace DevTools diagnostics. Qwen Computer Use is reserved for
native desktop UI. No Windows-control MCP is installed. Product Demo Studio
owns deterministic capture/composition after Product Experience Engineering
issues a current `DEMO-READY` handoff.

| Agent | Token Plan | MCP/config | Skill/plugin mechanism | Browser | Windows | Permission boundary | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hermes | `custom:qwencloud`, `qwen3.7-max`, `QWEN_API_KEY`, Anthropic endpoint | `%LOCALAPPDATA%\hermes\config.yaml`, `mcp_servers` YAML | Hermes loose skills | Native browser for quick use; DevTools MCP for evidence | QwenCloud documents WSL2; installed native runtime is validated separately | Dedicated QA profile; no inline key | `hermes mcp test chrome-devtools` |
| Claude Code | `ANTHROPIC_AUTH_TOKEN`, Anthropic base, preview default/stable subagent | `~/.claude/settings.json`, `~/.claude.json` | Native plugin plus user skills | Task-scoped DevTools via browser skill | QwenCloud documents WSL/Git Bash | Existing plugin enablement preserved; external writes still require approval | `claude mcp list`, `/skills` |
| Cursor | Cursor subscription or optional compatible provider configured in the UI | AgentHub-managed remote MCP plus optional project `.cursor/mcp.json` | Native local plugins, global Agent Skills, subagents, and `.cursor/rules/*.mdc` | Native browser tools; task-scoped DevTools only when needed | Native IDE | Active; unrestricted launcher is centrally managed and external effects remain task-authorized | non-paid version, plugin, config, and MCP discovery checks |
| OpenCode | `@ai-sdk/anthropic`, stable Qwen default | `~/.config/opencode/opencode.json`, `mcp` local command array | `~/.config/opencode/skills` | Task-scoped DevTools via browser skill | Native paths validated | Browser tools ask; use a dedicated browser agent | `opencode mcp list` |
| Qwen Code | OpenAI-compatible models with canonical `QWEN_API_KEY` (`envKey` is configurable) | `~/.qwen/settings.json`, `mcpServers`, `mcp.allowed` array | Native extensions plus `~/.qwen/skills` | Task-scoped DevTools; Computer Use only for native UI | Native driver is cross-platform but desktop exposure remains high risk | MCP allowlist; restart after Computer Use changes | `qwen --list-extensions`; interactive `/mcp` after token rotation |

The applied fleet mode is task-scoped. No host persists
`npx -y chrome-devtools-mcp@latest`; native browser tools are preferred and the
upstream command is launched only by the owning skill when needed. Antigravity
can attach to its built-in browser on 9222. The older `Shared` port 9333 and
four-host `Isolated` ports 9341–9344 remain optional controlled-diagnostics
modes, not the fleet default.
