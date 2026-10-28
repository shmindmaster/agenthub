# windows-desktop

Native Windows desktop control for every coding-agent host, through the
unmodified upstream [CursorTouch Windows-MCP](https://github.com/CursorTouch/Windows-MCP)
server (`windows-mcp==0.8.8` on PyPI, MIT). AgentHub supplies the pin, the
tool allowlist, the plugin packaging and the `use-windows-mcp` skill. It does
not copy upstream code.

## Activation

Plugin-gated, like `repowise` and `slack`. The MCP entry lives only in this
package's `.mcp.json` (Claude, Cursor) and `mcp.codex.json` (Codex). Sync does
not write it into any host MCP config, because a stdio server named there starts
at every session. Enable the plugin for a desktop task and disable it after.
Nothing is registered as a logon task, Run key or service.

```powershell
claude plugin install windows-desktop@agenthub   # once; installs ENABLED
claude plugin disable windows-desktop@agenthub   # immediately: rest state is installed-disabled
claude plugin enable windows-desktop@agenthub    # for a desktop task; disable again after
```

Enabling loads the server into every running Claude session, not only the one
doing the task. Disabling does not stop servers that are already running; they
exit with their sessions. See the skill for the measured fan-out and the
headless `--plugin-dir` alternative.

Codex: `codex plugin add windows-desktop@agenthub`, then
`codex plugin remove windows-desktop@agenthub`. Other hosts:
`skills/use-windows-mcp/SKILL.md`.

Each enabled host session runs its own `uvx` → Python process. A single shared
HTTP server was rejected on purpose: it would keep a localhost listener open
that lets any local process drive the mouse and keyboard, and only one coding
host runs at a time on this machine.

## Safety defaults

- `--tools` allowlist: `Screenshot`, `Snapshot`, `DisplayInventory`,
  `ControlStatus`, `Wait`, `WaitFor`, `Click`, `Type`, `Scroll`, `Move`,
  `Shortcut`, `App`, `MultiSelect`, `MultiEdit`, `Notification`.
- Not exposed: `PowerShell`, `Registry`, `FileSystem`, `Process`, `Clipboard`,
  `Scrape`. Upstream enables every tool by default and recommends no
  restriction. AgentHub removes the ones that duplicate host shell and file
  tools, which would otherwise bypass the host's permission prompts.
- `ANONYMIZED_TELEMETRY=false`. Upstream sends PostHog telemetry by default.
- stdio transport only. No HTTP listener, no auth key to manage.

Upstream's own warning applies: Windows-MCP "operates with full system access
and can perform irreversible operations", and its user-takeover pause is
best-effort rather than a security boundary.

## Requirements

Windows 10/11, `uv` on PATH. uv provisions Python 3.14 (upstream's floor) on
first launch.
