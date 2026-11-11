# Kiro development setup

Kiro CLI 3.2.0 was exercised on Windows on 2026-11-11. The owner authorized broad development capabilities and no routine tool-approval prompts. This is a local IDE/CLI configuration, not a cloud-account configuration or a Crew rollout.

## Direct development and dispatched work are separate

Direct development uses the existing `ah-project-engineer` profile, with `tools: ["*"]`, `model: "auto"`, `includeMcpJson: true`, `includePowers: true`, and an agent-level `all` allow rule. Researcher and reviewer profiles retain read/web-only toolsets. The dispatcher continues to name the restricted `ah-peer` explicitly; changing the direct default does not widen its toolset.

CLI settings are written through the native `kiro-cli settings` command:

```powershell
kiro-cli settings chat.defaultAgent ah-project-engineer
kiro-cli settings chat.agentEngine v3
kiro-cli settings acp.agentEngine v3
kiro-cli settings chat.defaultModel auto
kiro-cli settings chat.disableInheritingDefaultResources false
kiro-cli settings chat.enableWorkflows true
kiro-cli settings chat.workflowLaunch large-tasks
```

On this version, `agent set-default ah-project-engineer` rejects a V3-only profile; the documented `chat.defaultAgent` setting works. Start a fresh chat from the actual repository root. In the IDE, select `ah-project-engineer` in the agent picker; the CLI default is not evidence of an IDE selection.

## Permissions

The user-scoped `~/.kiro/settings/permissions.yaml` contains:

```yaml
rules:
  - capability: all
    effect: allow
```

The installed runtime rejects a file containing only `policies: [allow-all]` with `Policy must contain a "rules" array`, despite the current web documentation describing that preset. Explicit rules were verified through real headless tool calls without `--trust-all-tools`.

This removes routine permission prompts, not Kiro's hardcoded protections. Explicit deny/ask rules still win, workspace trust remains, and `all` excludes `sandbox_network`. Production changes, spending, secrets and external communication retain the task's authorization boundaries. Do not bypass an invariant through another tool.

## Capability sources

The engineer references existing skill sources through `skill://` globs, rather than copying or republishing packages:

- User and workspace `.kiro/skills/**/SKILL.md`.
- AgentHub `packages/product`, `packages/browser`, `packages/repowise` and `packages/mobile-development` skill trees.
- The installed official Clerk skill tree, currently exposed from the owner's Amp vendor-plugin installation. This is a local dependency: if that installation moves or is removed, update the resource path. It does not establish a Kiro Clerk MCP connection.

The profile also loads the canonical personal fleet policy. Owner steering remains intact except for the authorized autonomy change and a pointer to current fleet/Linear coordination. Absolute source references work locally, not in cloud sessions; they must be bound to the destination machine when setting up another host.

Tool Search remains enabled with zero thresholds, automatic compaction remains on, and billed session recap remains off. The existing eight Powers remain available on demand: Context7, Exa, Tavily, Miro codegen, Stripe, ElevenLabs, AWS Amplify and design-system scaffold. Discovery does not establish provider authentication or permission to spend. Existing Linear and AWS MCP configuration was preserved without copying credentials.

## Measured verification and limits

- Native agent validation exited 0.
- A fresh V3 session executed `17*29` and returned 493, and read the repository README without approval.
- Another fresh session using the saved default wrote a synthetic file through the native write tool; an independent readback matched `KIRO_SETUP_OK`.
- The saved-default session invoked the read-only reviewer, which read the README, and called Linear `get_issue` for the session protocol successfully.
- Product build/verify, browser automate, RepoWise and official Clerk skills were discovered by the running agent; its Powers tool listed all eight existing Powers.
- A fresh session in ABACare inherited its repository guidance and identified `dev`, AWS ECS, Clerk and synthetic-data-only verification. It discovered the same engineering skills without editing ABACare or claiming product work.
- Negative control: under the unchanged `ah-peer`, `doctl version` was denied by `doctl *`, while `Write-Output PEER_ALLOWED_OK` completed. The broad user allow did not erase the dispatch restriction.
- ACP `initialize` negotiated protocol 1, image context, HTTP/SSE MCP and workflow extensions. `_kiro/workflow/listRecipes` loaded the existing three-step `ah-project-delivery` plan (planner, coder, semantic reviewer).
- The runtime offers `save_workflow_definition`, not the documentation's `validate_workflow`. Recipe discovery is proven; full workflow execution is not. Saving a workflow is a write, not a validation-only substitute.
- An initial smoke from an ignored scratch directory discovered no skills or Powers; the repository-root run did. Do not use that scratch-directory result as evidence of a missing global installation.

IDE UI, cloud synchronization, provider authentication for the eight Powers, production delivery and Crew were not exercised. No startup hook, schedule, local model, new credential or standing service was created.

## Official references

- [ACP](https://kiro.dev/docs/acp/), [CLI ACP](https://kiro.dev/docs/cli/acp/), [permissions](https://kiro.dev/docs/permissions/), [settings](https://kiro.dev/docs/reference/settings/).
- [Steering](https://kiro.dev/docs/steering/), [skills](https://kiro.dev/docs/skills/), [MCP](https://kiro.dev/docs/mcp/).
- [Custom agents](https://kiro.dev/docs/custom-agents/), [creating](https://kiro.dev/docs/custom-agents/creating/), [configuration](https://kiro.dev/docs/custom-agents/configuration-reference/), [built-ins](https://kiro.dev/docs/custom-agents/built-in/), [subagents](https://kiro.dev/docs/custom-agents/subagents/), [examples](https://kiro.dev/docs/custom-agents/examples/).
- [Workflows](https://kiro.dev/docs/workflows/), [authoring](https://kiro.dev/docs/workflows/authoring/), [patterns](https://kiro.dev/docs/workflows/patterns/), [management](https://kiro.dev/docs/workflows/manage/).
- [Powers](https://kiro.dev/docs/powers/), [installation](https://kiro.dev/docs/powers/installation/), [creation](https://kiro.dev/docs/powers/create/).
