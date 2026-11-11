# Kiro fleet: steering, workflow recipes and profile installer (SH-4419)

This runbook covers the repository artifacts under `packages/coding-agent-dispatch/kiro/`. It complements `kiro-development.md`, which describes the owner's direct-development setup. Nothing described here has been installed into a user profile by the change that introduced it.

## Observed state

Audit date: 2026-11-11. Method: read-only listing of names and counts under `%USERPROFILE%\.kiro`, `kiro-cli --version`, and file metadata of the IDE install. The IDE was not launched. No credential or token file was opened; only the key names of the MCP configuration were listed.

| Item | Observed |
| --- | --- |
| Kiro CLI | `kiro-cli 3.2.0` |
| Kiro IDE | 1.4.154 (read from the install's `package.json` and executable file metadata, no launch) |
| Agent profiles (`agents/*.json`) | 28 JSON profiles |
| Steering files (`steering/`) | 2: `AGENTS.md`, `aws-agent-rules.md` |
| Skills (`skills/`) | 28 directories: `ah-project-delivery`, `issues`, `daytona`, `launch-with-aws`, `signing-in-to-aws` and 23 `aws-*`/`amazon-bedrock` skills |
| Powers (`powers/installed.json`) | 8 installed |
| MCP servers (`settings/mcp.json`, names only) | 2: `linear`, `aws-mcp` |
| Workflow recipes (`workflows/`) | 1: `ah-project-delivery.workflow.json` |
| Permissions | `settings/permissions.yaml` holds one rule, `all: allow` |

Ownership of the 28 agent profiles:

- AgentHub-managed (repository names `ah-architect`, `ah-engineer`, `ah-incident`, `ah-readonly`, `ah-reviewer`, `ah-tester`): 6 present. Compared by SHA-256 against `kiro/agents/*.json`, `ah-readonly` is current and the other five DIFFER from the repository copy (drift; cause not established, line endings or content not diffed).
- Dispatcher/direct profiles outside `kiro/agents/` (`ah-peer`, `ah-project-engineer`, `ah-project-researcher`, `ah-project-reviewer`): 4, owned by the dispatcher setup and `kiro-development.md`, not by this installer. A stray `ah-peer.json.bak` backup copy also exists (1 file).
- Kiro Crew (`kirocrew*.json`, 14) and auto-improvement (`auto-improvement--*.json`, 4): 18, produced by the Crew product, not AgentHub. Left alone.
- Remaining entries are non-profile files (`agent_config.json.example`, lock files, `scripts/`).
- Steering: `AGENTS.md` is owner-authored global policy; `aws-agent-rules.md` is AWS toolkit-managed. Neither is AgentHub-managed by this change.
- Skills: `ah-project-delivery` is AgentHub-related; the `aws-*` set is AWS toolkit-managed; `issues` is the Linear skill. Per-skill provenance was not read file by file: NOT ESTABLISHED.

Duplicates (same capability reachable two ways):

- Linear: the `linear` MCP server and the `issues` skill both reach Linear.
- AWS: `aws-mcp` serves documentation and skills (`retrieve_skill`) while the same `aws-*` skills are installed locally.
- Stripe and Tavily: Power directories exist for both (`powers/` holds Context7, Exa, Tavily, Miro codegen, Stripe, ElevenLabs, AWS Amplify and design-system scaffold). They are not in `mcp.json`; whether the Powers register their own servers is NOT ESTABLISHED.
- `ah-project-delivery` exists as both a skill and a workflow recipe.

NOT ESTABLISHED: whether the IDE currently selects `ah-project-engineer`; per-skill ownership; why five managed profiles differ from the repository.
