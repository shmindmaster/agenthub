# Agentic Plugin Ecosystem

Before substantive work, read `docs/cross-agent-operating-charter.md` and `docs/cross-agent-memory-seed.md`. Classify the task before acting. Personal capability work must never use a client repository, tracker, documentation system, communication system, identity, dataset, or deployment as its control plane or test fixture; split mixed personal/client work into separate tasks.

Treat plugins, agent plugins, extensions, agents, constructors, MCP servers, and CLI integrations as one ecosystem with host-native adapters. Before adding or changing a capability, identify its single owner, prefer MCP/API reuse over duplicated logic, and check every registered host for an appropriate exposure path.

Never copy credentials, tokens, evidence, indexes, or model data into an adapter. Use environment-variable references and user-mediated OAuth.

Use official host documentation as the packaging authority. If a host has no verified public specification, record it as discovery-required rather than inventing a plugin format. Validate manifests, duplicate ownership, authentication prerequisites, and read-only health checks before declaring an integration ready.

## GitHub access

Use the `gh` CLI rather than a GitHub MCP server. This machine has three GitHub
accounts: `shmindmaster`, `sh-pendoah`, and `sarosh-pendoah`. Before any
repository operation, run `gh auth status`; when the intended account is not
active, use `gh auth switch --user <account>`. State which account is active
when it materially affects the operation.
