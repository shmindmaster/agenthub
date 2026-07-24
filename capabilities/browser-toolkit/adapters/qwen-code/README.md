# Qwen Code adapter

Configuration lives at `~/.qwen/settings.json`; skills live at
`~/.qwen/skills`. The native settings fragment enables Chrome DevTools MCP and
the built-in Computer Use tool.

Computer Use is for required native desktop interactions, not ordinary browser
testing. Its first use downloads a pinned driver to `~/.qwen/computer-use`.
Current Windows driver signing and desktop-control exposure must be accepted
explicitly before use. Restart Qwen Code after changing
`tools.computerUse.enabled`.

Verify with `/mcp`, `/skills`, one Qwen response, the controlled browser smoke,
and a separate synthetic native-UI smoke only when the workflow requires it.
