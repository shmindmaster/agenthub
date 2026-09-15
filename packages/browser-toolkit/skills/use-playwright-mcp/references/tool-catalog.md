# Playwright MCP — tool catalog pointer

**Canonical upstream:**  
https://github.com/microsoft/playwright-mcp/blob/main/README.md

Package pin (fleet): `@playwright/mcp@0.0.79` — see `registry/mcps.json` and
`packages/browser-toolkit/.mcp.json`.

Do not fork the full parameter schema into AgentHub. When parameters change,
trust upstream README Tools and keep `SKILL.md` as the routing/cheat sheet only.

## Naming rule

Live tools use the Microsoft Playwright MCP `browser_*` vocabulary, for example:

- `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`
- `browser_tabs`, `browser_console_messages`, `browser_network_requests`
- `browser_take_screenshot`, `browser_evaluate`, `browser_wait_for`

Do **not** use retired Chrome DevTools MCP names (`list_pages`, `take_snapshot`, `fill_form`, `lighthouse_audit`, …) against this server.

## CLI vs MCP

- Coding agents / token-efficient capture → Playwright CLI + skills  
  https://playwright.dev/docs/getting-started-cli
- Persistent exploratory loops → Playwright MCP (this catalog)

## Related fleet docs

- `docs/development/chrome-cdp.md` — migration notes from the retired chrome-devtools stack
- `registry/mcps.json` — `playwright`
- Sibling catalogs: `use-playwright-cli`, `use-playwright-test`
