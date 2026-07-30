# Architecture and agent comparison

Chrome DevTools MCP is selected as the shared live-browser diagnostics layer
because it can attach to a visible, authenticated, dedicated Chrome profile and
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
| Claude Code | `ANTHROPIC_AUTH_TOKEN`, Anthropic base, preview default/stable subagent | `~/.claude/settings.json`, `~/.claude.json` | Native plugin plus user skills | DevTools MCP | QwenCloud documents WSL/Git Bash | Existing plugin enablement preserved; external writes still require approval | `claude mcp list`, `/skills` |
| Cursor | Cursor subscription or optional compatible provider configured in the UI | AgentHub-managed global MCP plus optional project `.cursor/mcp.json` | Native local plugins, global Agent Skills, subagents, and `.cursor/rules/*.mdc` | AgentHub browser tools; optional isolated DevTools MCP | Native IDE | Active; unrestricted launcher is centrally managed and external effects remain task-authorized | non-paid version, plugin, config, and MCP discovery checks |
| OpenCode | `@ai-sdk/anthropic`, stable Qwen default | `~/.config/opencode/opencode.json`, `mcp` local command array | `~/.config/opencode/skills` | DevTools MCP with `ask` permission | Native paths validated | Browser tools ask; use a dedicated browser agent | `opencode mcp list` |
| Qwen Code | OpenAI-compatible models with canonical `QWEN_API_KEY` (`envKey` is configurable) | `~/.qwen/settings.json`, `mcpServers`, `mcp.allowed` array | Native extensions plus `~/.qwen/skills` | DevTools MCP; Computer Use only for native UI | Native driver is cross-platform but desktop exposure remains high risk | MCP allowlist; restart after Computer Use changes | `qwen --list-extensions`; interactive `/mcp` after token rotation |

Applied browser mode is `Shared` on 9333, one interactive owner at a time.
`Isolated` mode assigns Claude/Qwen/OpenCode/Hermes ports 9341–9344 and separate
profiles. Port 9222 belongs to the normal browser and is excluded.
