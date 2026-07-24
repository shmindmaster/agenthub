# OpenCode adapter

Global configuration lives at `~/.config/opencode/opencode.json`; global skills
live at `~/.config/opencode/skills`. The fragment uses the documented local MCP
command array and asks before Chrome DevTools tool calls.

For least privilege, create a dedicated OpenCode browser-testing agent and
disable `chrome-devtools_*` for unrelated agents. Verify with `opencode mcp
list`, the skill tool, one model response, and the controlled browser smoke.
