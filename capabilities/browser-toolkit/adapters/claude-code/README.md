# Claude Code adapter

- Token Plan variables live in `~/.claude/settings.json`; the token itself is
  `ANTHROPIC_AUTH_TOKEN` and is never stored here.
- User MCP configuration lives in `~/.claude.json`. The configuration script
  merges `mcp.fragment.json`.
- Shared skills are junctioned into `~/.claude/skills`.
- Verify interactively with `/mcp`, `/skills`, one model response, and the
  browser smoke workflow. Permissions should require confirmation for writes
  and external side effects.

Official Windows support is through WSL or Git Bash according to the QwenCloud
client guide. Native PowerShell configuration paths are still handled by the
toolkit script for an existing native installation.
