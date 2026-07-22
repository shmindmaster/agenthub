# Qwen Code adapter

Qwen Code consumes shared repository instructions through `AGENTS.md`, Qwen-specific instructions through `QWEN.md`, shared MCP definitions generated from `registry/mcps.json`, and Qwen-native subagents from `~/.qwen/agents`.

`Sync-AgentCapabilities.ps1` also creates Qwen extension adapters under this
directory and junctions them into `~/.qwen/extensions`. Each adapter references
the canonical capability's `skills` directory rather than copying it, so Qwen
receives the same skill packages as the other active coding agents without a
second source of truth.

Secrets remain in environment variables or host-managed OAuth storage. Never write API keys, PATs, tokens, or authorization headers into generated registry files.
