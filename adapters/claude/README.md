# Claude Code adapter

Claude Code is a native orchestration host. Its generated policy, skills,
subagents, plugins, MCP configuration, and user settings must follow its own
documented locations under `%USERPROFILE%\.claude`; an `AGENTS.md` source is
imported by the generated `CLAUDE.md` rather than duplicated.

## Native surfaces

- Use `CLAUDE.md` and `.claude/rules/` for concise always-on and path-scoped
  guidance. Use skills for on-demand procedures and reference material.
- Compile the shared scout, implementer, reviewer, and verifier contracts into
  Claude subagent definitions. Those definitions can also serve as agent-team
  teammates; do not create a second team-role registry.
- Use worktrees for parallel write isolation. Agent teams are experimental and
  remain opt-in; they must not be globally enabled by this adapter.
- Treat dynamic workflows as named, reviewable orchestration capabilities.
  Do not enable ultracode or install an unreviewed workflow globally.
- Use a Claude plugin only when a capability truly needs a bundle of skills,
  subagents, hooks, or MCP entries. Reuse the same MCP/API contract and
  environment-variable names; never package credentials.
- Code intelligence is supplied by language plugins. Do not deploy a generic
  LSP configuration where a documented language plugin is required.
- Auto memory is native, project-local, and shared by that repository's
  worktrees. It is not a fleet synchronization channel.
- `claude -p` is the automation entry point. For deterministic automation,
  use `--bare` and pass settings/MCP/agents/plugins explicitly.

## Guardrails

- Hooks, channels, artifacts, and scheduled tasks require a named capability
  and focused validation. Do not make a broad global hook or use session cron
  as a durable scheduler.
- `--dangerously-skip-permissions` is the documented full-bypass flag for an
  authorized unattended run. It does not broaden the portfolio policy around
  deployments, credentials, destructive cleanup, or external communication.
- Claude plugins may also be consumable by VS Code agent plugins, but each
  host's manifest and validation remain independent.
