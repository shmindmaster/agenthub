# MCP ownership and placement — updated 2026-07-29

The fleet uses one ownership registry with host-specific exposure modes. An
installed plugin or native connector owns its host surface. Remote services
without a native owner are candidates for one authenticated streaming gateway.
Repository tools remain on-demand and are never persisted in host
configuration by fleet synchronization. Chrome DevTools MCP is the explicit
exception requested for every supported host: it is persisted with the
upstream README configuration and launches only when a host uses one of its
tools.
Gateway generation is disabled until the shared production profile passes.
Docker MCP Toolkit is now enabled and
a remote-only profile partially passed: Linear initialized, Context7 initialized
and completed a read-only call, and Notion was blocked by missing OAuth. A
separate Firecrawl custom-remote POC proved the loopback bearer gate (401
without auth, 200 with auth), session issuance, and tool discovery without
executing a quota-bearing tool. No live host configuration is generated from
those POCs.

The production declaration is intentionally one profile bound to one endpoint.
It contains only the four-service intersection shared by every enabled,
non-held host: Context7, Exa, Firecrawl, and Tavily. Services with host-specific
plugin or native ownership remain direct instead of creating per-host gateway
profiles that a single endpoint cannot isolate concurrently.

| MCP | Registry owner | Current placement decision |
| --- | --- | --- | --- |
| `github` | MCP registry | Codex native connector, Claude and Copilot plugins, gateway candidate elsewhere |
| `linear` | MCP registry | Codex plugin, gateway candidate elsewhere |
| `context7`, `tavily`, `exa` | MCP registry | Gateway candidates on all eligible hosts |
| `notion` | MCP registry | Claude and Codex plugins, gateway candidate elsewhere |
| `firecrawl` | MCP registry | Gateway candidate on Codex and elsewhere; the Codex `firecrawl-ops@agenthub` package remains installed as skills-only and declares no bundled MCP server |
| `adobe-for-creativity` | MCP registry | Codex plugin, gateway candidate elsewhere |
| `canva` | MCP registry | Codex native connector, gateway candidate elsewhere |
| `descript` | Product Demo Studio capability | Claude and Codex plugins, gateway candidate elsewhere |
| `chrome-devtools` | Browser Toolkit capability | On-demand through the browser skills or host-native browser capability; never persisted in fleet host configuration |
| `repocontext` | RepoContext capability | On-demand through the skill/local profile until its remote contract is production-ready |
| `playwright`, `brave-search` | MCP registry | On-demand local; never fleet-wide persistent |

## Rules

- `registry/mcps.json` records the single service/capability owner.
- `registry/native-connectors.json` records the effective host exposure:
  `plugin-owned`, `native-connector`, `shared-gateway`, or `local-only`.
- Fleet synchronization emits shared remotes only. Every MCP with
  `activationMode: on-demand-local`, including Chrome DevTools, must be suppressed from every host config,
  including stale registrations left by an older sync.
- Do not emit a direct MCP registration when a plugin/native connector owns the
  surface. Once a gateway profile is validated and explicitly enabled, replace
  only its listed direct remotes with the single `agenthub-gateway` endpoint.
- Keep `firecrawl-ops@agenthub` skills-only. Do not add `mcpServers` to its
  manifest or restore its `.mcp.json` without deliberately reassigning the
  `firecrawl` owner away from `registry/mcps.json` and reviewing every host
  exposure.
- `registry/gateway-profiles.json` records the partial POC. Linear and Context7
  have observed remote snapshot mappings; Notion is OAuth-blocked. Container
  catalog servers are Windows-blocked by missing `socat`. Firecrawl's catalog
  entry is container-backed, so its official remote HTTP endpoint needs a
  custom remote snapshot passed its transport/auth/tool-discovery POC. The
  container image remains blocked; only the custom remote mapping is eligible
  for a future production profile.
- Do not promote inactive private-corpus MCP packages into the global fleet.
- Historical labels `sh-knowledge`, `knowledge`, `legal`, and `shwiki` are
  migration aliases to `repocontext`; generated configuration never emits them.
