# AssemblyAI plugin

Thin AgentHub wrapper for AssemblyAI. It holds one routing skill and points each host at AssemblyAI's two hosted MCP servers. It runs no local process and stores no key.

## Contents

| Path | Host |
|---|---|
| `skills/assemblyai/SKILL.md` | Every host. The only skill text |
| `plugin.json`, `mcp.json` | Agent Plugins 1.0.0 (Copilot, Codex, Cursor) |
| `.claude-plugin/plugin.json`, `.mcp.json` | Claude Code, plus Grok and Factory, which read Claude layouts |
| `.cursor-plugin/plugin.json` | Cursor |
| `.antigravity-plugin/plugin.json`, `mcp_config.json` | Antigravity |
| `gemini-extension.json` | Gemini CLI |

Servers:

- `assemblyai`: `https://mcp.assemblyai.com/mcp` ([source](https://www.assemblyai.com/docs/mcp-server)). OAuth sign-in. Usage is billed.
- `assemblyai-docs`: `https://assemblyai.com/docs/mcp`. No sign-in, free.

## Why it wraps instead of copies

`AssemblyAI/assemblyai-skill` has no licence, so its text cannot be copied here. The skill pins the vendor's own docs and names `npx skills add AssemblyAI/assemblyai-skill` as an optional install. `AssemblyAI/assemblyai-mcp` is MIT, and this package points at its hosted endpoint rather than a copy.

## Install

Keep the plugin off until a task needs it. The GitHub routes work once this package is on `main`; until then, use a local path where the host accepts one.

Status: **help** means checked against the installed CLI's help, **docs** means checked against the vendor's page, **unverified** means neither. None of these was run here.

| Host | Install | Off switch | Status |
|---|---|---|---|
| Claude Code | `claude plugin marketplace add shmindmaster/agenthub`, then `claude plugin install ah-assemblyai@agenthub` | `claude plugin disable ah-assemblyai@agenthub` | help |
| Codex | `codex plugin marketplace add shmindmaster/agenthub`, then `codex plugin add ah-assemblyai@agenthub` | `[plugins."ah-assemblyai@agenthub"] enabled = false` in `~/.codex/config.toml` | help, docs |
| Cursor | Copy this folder to `~/.cursor/plugins/local/assemblyai`, then run Developer: Reload Window. Symlinks from outside that folder are skipped | Remove the folder | docs |
| Copilot CLI | `copilot plugin install shmindmaster/agenthub:packages/assemblyai` | `copilot plugin disable assemblyai` | help |
| Gemini CLI | `gemini extensions install ./packages/assemblyai`, or `gemini extensions link ./packages/assemblyai` | Unverified | docs |
| Antigravity | `agy plugin install ./packages/assemblyai`, then `agy plugin enable assemblyai` | `agy plugin disable assemblyai` | help, docs |
| Grok | `grok plugin install shmindmaster/agenthub#packages/assemblyai` | `grok plugin disable assemblyai` | help |
| Factory | `droid plugin marketplace add https://github.com/shmindmaster/agenthub`, then `droid plugin install ah-assemblyai@agenthub --scope user`. The marketplace name comes from the source, so confirm it with `droid plugin marketplace list` | `enabledPlugins` | help, docs |
| OpenCode | Copy `skills/assemblyai` to `~/.config/opencode/skills/`, then `opencode mcp add assemblyai --url https://mcp.assemblyai.com/mcp --global` and `opencode mcp auth assemblyai` | Remove the entry | help, docs |
| Cline | Copy `skills/assemblyai` to `~/.cline/skills/` | Remove the folder | unverified: path from `registry/` only |
| Amp | Copy `skills/assemblyai` to `~/.config/amp/skills/` | Remove the folder | unverified: path from `registry/` only |
| Warp | Copy `skills/assemblyai` to `~/.warp/skills/` | Remove the folder | unverified: path from `registry/` only |
| Windsurf | Copy `skills/assemblyai` to `~/.codeium/windsurf/skills/` | Remove the folder | unverified: path from `registry/` only |

Also unverified: that Antigravity and Gemini complete OAuth against the hosted server.

## Acceptance prompts

Run one in a fresh session on that host. A pass prints the marker and the two URLs from the skill. These have not been run.

| Host | Prompt |
|---|---|
| Claude Code | `Load the assemblyai skill, print AAI-OK-CLAUDE, then list the two URLs it says to read first.` |
| Codex | `Load the assemblyai skill, print AAI-OK-CODEX, then list the two URLs it says to read first.` |
| Cursor | `Load the assemblyai skill, print AAI-OK-CURSOR, then list the two URLs it says to read first.` |
| Copilot CLI | `Load the assemblyai skill, print AAI-OK-COPILOT, then list the two URLs it says to read first.` |
| Gemini CLI | `Load the assemblyai skill, print AAI-OK-GEMINI, then list the two URLs it says to read first.` |
| Antigravity | `Load the assemblyai skill, print AAI-OK-ANTIGRAVITY, then list the two URLs it says to read first.` |
| Grok | `Load the assemblyai skill, print AAI-OK-GROK, then list the two URLs it says to read first.` |
| Factory | `Load the assemblyai skill, print AAI-OK-FACTORY, then list the two URLs it says to read first.` |
| OpenCode | `Load the assemblyai skill, print AAI-OK-OPENCODE, then list the two URLs it says to read first.` |
| Cline | `Load the assemblyai skill, print AAI-OK-CLINE, then list the two URLs it says to read first.` |
| Amp | `Load the assemblyai skill, print AAI-OK-AMP, then list the two URLs it says to read first.` |
| Warp | `Load the assemblyai skill, print AAI-OK-WARP, then list the two URLs it says to read first.` |
| Windsurf | `Load the assemblyai skill, print AAI-OK-WINDSURF, then list the two URLs it says to read first.` |

## Keys

The MCP entries carry no key. Sign-in is OAuth. Code that calls the REST API reads `ASSEMBLYAI_API_KEY` from the environment. Media work goes through `media-studio`, not this plugin.
