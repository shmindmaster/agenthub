# Browser Toolkit

One browser-quality plugin with one on-demand MCP server and three focused skills.

## Architecture

- Chrome DevTools MCP 1.6.0 owns interactive headed Chrome inspection, screenshots,
  accessibility snapshots, console, network, Lighthouse, performance traces,
  screencasts, and heap analysis.
- Playwright CLI 0.1.17 is invoked from the interactive-testing skill for compact
  multi-step actions, headed sessions, traces, screenshots, and recordings.
- Playwright MCP is intentionally not included. It overlaps browser automation and
  would create another persistent tool schema and local worker.

The MCP server starts only when the installed plugin is used. Its default browser is
headed but isolated in a temporary profile that is deleted when Chrome closes. It does
not connect to the normal personal Chrome profile. Usage statistics, update checks, and
CrUX URL lookups are disabled.

## Validation

```powershell
python C:\Users\SaroshHussain\.codex\skills\.system\plugin-creator\scripts\validate_plugin.py .
npx -y chrome-devtools-mcp@1.6.0 --help
```
