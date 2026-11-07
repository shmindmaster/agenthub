# Claude Desktop gateway tool loading

Claude Desktop gateway deployments suppress MCP tool search by default. Setting
`ENABLE_TOOL_SEARCH=true` in Claude Code settings does not remove that Desktop
suppression. Set the documented native managed key `toolSearchEnabled` to boolean
`true` only after verifying the gateway's request compatibility. On Windows the
managed configuration lives under `Software\Policies\Claude`.

The setting adds deferred tool schemas and `tool_reference` blocks. Anthropic
passthrough and an Anthropic-to-OpenAI Chat translation are different routes:
do not assume passthrough compatibility proves Chat translation compatibility.
Do not increase a model's advertised context window to hide eager tool loading.

## Opt-in Chat translation compatibility

`scripts/claude_gateway_callback.py` is a LiteLLM pre-call hook for the local
Runware model aliases. It leaves other providers and endpoints untouched. It
supports client-side `ToolSearch`, keeps non-deferred tools and discovered tools,
and retains schemas for tools used earlier in the conversation. It turns client
tool references into ordinary text before the Chat adapter sees them. It does
not implement Anthropic's server-side tool-search tools.

Mount both Python files from `scripts/` beside the gateway configuration and add
this opt-in callback to the existing `litellm_settings` block, preserving any
existing callbacks:

```yaml
litellm_settings:
  callbacks:
    - claude_gateway_callback.deferred_tools
```

Both files must be importable by the gateway process. Keep the original model
routes, credential references and unrelated settings. Back up only the affected
configuration and the selected native property before changing them. Never
export a complete managed-policy registry branch: it may contain credentials.

The hook refuses a loaded tool catalog above 160,000 UTF-8 bytes before an
upstream call. This is a conservative schema-size guard, not a token limit or a
currency spending cap. Repeated discovery can reach it; reduce the active
integrations rather than disabling the guard. Unsupported server tools and
missing discovered tools also fail locally. HTTP 402 prevents an eager-loading
retry; it does not indicate that the upstream account ran out of credit.

## Verify before resuming paid traffic

1. Run `pwsh -NoProfile -File tests/Test-ClaudeGatewayTools.ps1`.
2. Run `tests/fixtures/claude-gateway-compat.py` inside the **exact deployed**
   LiteLLM image with the checkout mounted read-only, `--network none` and
   `LITELLM_LOCAL_MODEL_COST_MAP=True`. It exercises the real translator with a
   synthetic search, discovery and tool-use round trip, including local refusal.
3. Configure the callback and native property, then read them back. Keep the
   paid gateway stopped while examining a cost incident.
4. A fresh Desktop session must show a search tool and deferred MCP schemas.
   Confirm the translated upstream request contains only loaded tools. Measure
   the first request and subsequent cache usage before declaring live acceptance.
   Offline translation tests alone do not prove fresh Desktop loading.

During an incident, preserve session and usage logs privately. Attribute usage
by session identifier, distinguish gateway estimates from provider billing, and
do not publish prompts, tool results, credentials or session identifiers.

Sources: [Desktop gateway tool search](https://claude.com/docs/third-party/claude-desktop/gateway#mcp-tool-search),
[native configuration](https://claude.com/docs/third-party/claude-desktop/configuration#toolsearchenabled),
[LiteLLM pre-call hooks](https://docs.litellm.ai/docs/proxy/call_hooks).
