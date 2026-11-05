# AH-Brave-Search plugin

Search the live web with the Brave Search API from any coding agent. One skill (`search`) drives a dependency-free Node client that returns trimmed, token-sized results. It runs no server and starts nothing until a search is made.

## Contents

| Path | Purpose |
|---|---|
| `skills/search/SKILL.md` | The only skill. Command choice and rules |
| `skills/search/scripts/brave.mjs` | Client for context, web, news, images, videos, places, POIs, suggest, spellcheck and answers |
| `skills/search/references/` | Parameters, places and answers detail, read on demand |
| `plugin.json`, `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `.antigravity-plugin/` | Host manifests |
| `tests/brave.test.mjs` | Offline tests against a local fake server |

## Key

Set `BRAVE_SEARCH_API_KEY`, or the existing `BRAVE_API_KEY`, in the environment. The client sends it only in a request header, refuses redirects, and never prints or stores it. Get a key at https://api.search.brave.com. Plans and prices are Brave's; `answers --research` is the costly command.

## Why a script and not an MCP server

Brave's own MCP server (`@brave/brave-search-mcp-server`) runs a local process per host session. This client runs only when a search is made, works the same on every host that reads skills, and returns less text per call.

## Test

```bash
node --test tests/brave.test.mjs
```

Source for the endpoint descriptions: brave/brave-search-skills (MIT). See `NOTICE`.
