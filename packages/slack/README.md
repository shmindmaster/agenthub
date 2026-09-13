# Slack (AgentHub)

Canonical Slack capability. AgentHub owns read/write authority, schemas, and
identity. Coding-agent hosts are frontends.

This is not a restore of the 2026-08-05 claude.ai Slack connector, and it is
not a distribution of Slack's hosted MCP.

## Contract

- Tools: `schemas/tools.json`
- Message shape: `schemas/message.json` (`raw` is required; IDs are never dropped)
- Identity: `schemas/identity.json` (`actor_mode` is `user` or `agent_bot`)
- Hash: `node packages/slack/mcp/contract.mjs` is imported by tests;
  `slackContractHash` is sha256 of sorted tool names plus canonical input schemas

## MCP

Stdio server, protocol 2025-11-25:

```text
node mcp/slack-mcp.mjs
```

`SLACK_BRIDGE_MODE=fixture` (default when no token is set) uses
`fixtures/workspace.json`. Live mode uses the Slack Web API with
`SLACK_USER_TOKEN` / optional `SLACK_BOT_TOKEN`.

Current fleet delivery is plugin-gated / OpenCode opt-in-disabled so the
server is not started at session start. Production distribution is the
AgentHub gateway (`http://127.0.0.1:8811/mcp` locally; a remote authenticated
endpoint for cloud agents) once `gateway-profiles.json` generation is proven.

## Official Slack plugin

`slackapi/slack-skills-plugin` may be installed as optional UX. It must not
become the Slack owner, and AgentHub must not republish it.
