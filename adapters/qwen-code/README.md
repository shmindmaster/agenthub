# Qwen Code adapter

Qwen Code consumes shared repository instructions through `AGENTS.md`, Qwen-specific instructions through `QWEN.md`, shared MCP definitions generated from `registry/mcps.json`, and Qwen-native subagents from `~/.qwen/agents`.

`agents/` is the managed source for the portable Scout, Implementer, Reviewer,
and Verifier roles. `Apply-FullAccessAgentProfile.ps1` copies those four named
agents into the Qwen user home while preserving any project-local agents and
unrelated user-defined agents. Project-local agents remain the appropriate
place for product-specific additions; they must not relax repository policy.

The user-authorized personal portfolio TypeScript LSP overlay is described in
`registry/qwen-lsp-projects.json`. It is deployed only where `.lsp.json` is
absent, so a repository-owned LSP configuration is always preserved. Qwen's
experimental LSP flag is supplied by the managed `qwen.cmd` launcher.

For headless work, use that launcher with `--prompt` and an explicit
`--output-format` (`json` or `stream-json` for automation). Hooks are enabled
by Qwen by default; no global shell hook is installed because hooks execute at
user privilege. Add a project-local hook only when that repository defines a
reviewed, narrow lifecycle requirement.

`Sync-AgentCapabilities.ps1` also creates Qwen extension adapters under this
directory and junctions them into `~/.qwen/extensions`. Each adapter references
the canonical capability's `skills` directory rather than copying it, so Qwen
receives the same skill packages as the other active coding agents without a
second source of truth.

Secrets remain in environment variables or host-managed OAuth storage. Never write API keys, PATs, tokens, or authorization headers into generated registry files.
