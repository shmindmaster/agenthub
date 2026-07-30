# Antigravity adapters

Retained surfaces:

- CLI: WinGet-managed `agy.exe`, headless-capable
- Desktop: `%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe`
- IDE: `%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe`

Repository `AGENTS.md` is authoritative. The current CLI has an official
plugin contract at `~/.gemini/antigravity-cli/plugins/<plugin>/plugin.json`,
plus native skills, MCP, hooks, and subagents. AgentHub therefore generates
the Product Demo Studio CLI adapter there. Desktop and IDE packaging remain
separate surfaces and are not inferred from the CLI format. Do not duplicate
the CLI binary in a second private install directory.
