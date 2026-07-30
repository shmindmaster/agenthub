# Cursor adapter — active

Cursor IDE and Cursor Agent were explicitly reauthorized on 2026-07-30. AgentHub
deploys the shared browser skills, native product plugins, MCP registry,
permissions, and launch policy. This adapter documents the optional
repository-local browser contract; it is not an independent configuration
authority and must not create a duplicate persistent MCP process.

1. If QwenCloud is used, confirm the applicable plan and configure its
   OpenAI-compatible provider manually in Cursor Settings >
   Models with a supported plan and matching base URL:
   - Token Plan Team Edition: `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`
   - Coding Plan: `https://coding-intl.dashscope.aliyuncs.com/v1`
2. Prefer the AgentHub-managed global MCP registry and browser skills. Use this
   repository-local `mcp.json` only when the repository needs an isolated
   browser endpoint that cannot be expressed by the global contract.
3. Use `browser-quality.mdc` only as a repository-scoped narrowing rule.
4. Verify plugin and MCP discovery plus the controlled browser smoke without a
   personal Chrome profile.

Cursor provider credentials are UI-managed and intentionally absent from this
adapter.
