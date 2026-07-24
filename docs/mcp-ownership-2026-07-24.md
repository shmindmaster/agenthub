# MCP ownership and placement — 2026-07-24

The fleet uses a hybrid MCP model. A native plugin or capability bundle owns
an MCP on the hosts where it is installed; genuinely cross-cutting services
remain direct global registrations. The synchronizer removes only an explicit
plugin-owned duplicate and preserves unrelated user MCP entries unless broad
pruning is requested.

| MCP | Current owner | Placement | Evidence / decision |
| --- | --- | --- | --- |
| `descript` | Product Demo Studio | Native plugin on Claude and Codex; direct fallback elsewhere | `packages/handoff-plugins/plugins/product-demo-studio/.mcp.json` and both installed native plugins |
| `notion` | Native Notion plugin where installed | Native plugin on Claude and Codex; direct fallback elsewhere | Installed Claude plugin and installed Codex `notion@openai-curated` plugin; global entry is suppressed on those hosts |
| `chrome-devtools` | Browser Toolkit capability | Direct, host-scoped | `registry/mcps.json` host allowlist; no verified bundle manifest owns this exact server |
| `shwiki-context` | ShWiki Context capability | Direct global | Shared read-only portfolio context; inactive private package aliases are not promoted |
| `linear` | Fleet infrastructure | Direct global | Cross-project delivery state, not a single skill bundle |
| `context7` | Fleet infrastructure | Direct global | General documentation lookup used across capabilities |
| `playwright` | Fleet infrastructure | Direct global | Shared isolated browser automation runtime |
| `firecrawl`, `tavily`, `exa`, `brave-search` | Fleet research infrastructure | Direct global | Multiple research workflows consume them; no active installed bundle owns the MCP definitions |
| `adobe-for-creativity`, `canva` | External creative connectors | Direct global for now | Official plugin caches exist, but no active managed native plugin owner was found; do not claim bundle ownership from cache presence alone |

## Rules

- Do not emit a direct MCP registration on a host when an enabled native plugin
  already declares the same server.
- Do not install a plugin merely to make a classification look symmetrical;
  install only when it replaces a duplicate or is explicitly requested.
- Do not promote inactive private-corpus MCP packages into the global fleet.
- `pluginOwnersByHost` in `registry/mcps.json` is the machine-readable
  ownership contract. It is intentionally host-specific because one plugin
  may be installed on only part of the fleet.
