# Upstream Notes

This package follows the Firecrawl V2 API, CLI, MCP, Agent, and workflow model without copying an upstream plugin verbatim. The workflow layer is adapted from `firecrawl/firecrawl-workflows` and kept harness-agnostic: each skill targets a concrete deliverable, preserves source evidence, and can be rerun with explicit inputs.

Primary references:

- https://github.com/firecrawl/firecrawl-workflows
- https://docs.firecrawl.dev/api-reference/v2-introduction
- https://docs.firecrawl.dev/sdks/cli
- https://docs.firecrawl.dev/mcp-server
- https://www.firecrawl.dev/agent

The local MCP uses `firecrawl-mcp` with an environment-variable key reference. Hosted keyless MCP is rate-limited and narrower; local or authenticated MCP is required for the full tool surface, local-file handling, webhooks, and higher limits.
