# Cursor offline adapter — provider held

This directory is implementation-ready but must not be copied into Cursor,
loaded, invoked, or smoke-tested while the portfolio Cursor provider hold is
active. Reauthorization requires the documented reviewed control-plane changes;
a single local setting is insufficient.

After reauthorization:

1. Confirm QwenCloud Token Plan Team Edition and Cursor Pro+.
2. Configure the OpenAI-compatible provider manually in Cursor Settings >
   Models with a supported plan and matching base URL:
   - Token Plan Team Edition: `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`
   - Coding Plan: `https://coding-intl.dashscope.aliyuncs.com/v1`
   (user input `...dashscope.alryuncs...` appears to contain a typo; the official
   docs value is `aliyuncs`.)
3. Copy `mcp.json` to the project `.cursor/mcp.json` and
   `browser-quality.mdc` to `.cursor/rules/`.
4. Install/junction shared Agent Skills using current Cursor skill paths.
5. Verify MCP discovery and the controlled browser smoke without exposing a
   personal Chrome profile.

Cursor provider credentials are UI-managed and intentionally absent from this
adapter.
