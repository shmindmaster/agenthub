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

## Audit and install

```powershell
# Audit (default): prints current, drift, missing or owner-authored per file. Writes nothing.
pwsh -NoProfile -File .\packages\coding-agent-dispatch\kiro\Install-KiroProfiles.ps1

# Apply: copies only the AgentHub-managed files named in the script's $ManagedFiles list.
pwsh -NoProfile -File .\packages\coding-agent-dispatch\kiro\Install-KiroProfiles.ps1 -Apply

# Redirect the target (used by the tests).
pwsh -NoProfile -File .\packages\coding-agent-dispatch\kiro\Install-KiroProfiles.ps1 -Apply -UserProfile <dir>
```

Managed names: agents `ah-architect`, `ah-engineer`, `ah-incident`, `ah-readonly`, `ah-reviewer`, `ah-tester`; steering `ah-invariants.md`, `ah-registry-change.md`, `ah-powershell-scripts.md`. Every other file in `agents/` or `steering/` is reported as owner-authored and never touched. The installer does not read or write MCP files, Powers or `permissions.yaml`, writes no backup copies, and prints the before and after SHA-256 of each file it changes. A managed name that has drifted is replaced, so keep owner edits in a differently named file. The workflow recipes are project artifacts and are not installed by this script.

## Roles

| Profile | Tools | Use for |
| --- | --- | --- |
| `ah-architect` | read, write, shell, web, Linear | Design and plans; no subagents |
| `ah-engineer` | read, write, shell, web, Linear, subagents `ah-reviewer`/`ah-tester` | Implementing a scoped change |
| `ah-incident` | read, write, shell, web, Linear | Production-symptom triage and root cause |
| `ah-readonly` | read, glob, grep, thinking, todo | Research and orientation; cannot write or run commands |
| `ah-reviewer` | read, shell, web, Linear | Independent Pass/Fail/Blocked review |
| `ah-tester` | read, write, shell | Running tests and fixing tests only |

The dispatcher reaches them with `-HostId kiro -Role <role>`; add `-ReadOnly` for the read-only profile. See `packages/coding-agent-dispatch/skills/dispatch/SKILL.md`. Dispatching was not exercised by this change.

## Steering

Format verified from the Kiro steering documentation (https://kiro.dev/docs/steering/): YAML front matter with `inclusion: always | fileMatch | manual | auto`, `fileMatchPattern` for file match, and `name` plus `description` for auto inclusion. `ah-invariants.md` is always on (under 60 lines); `ah-registry-change.md` is auto-included; `ah-powershell-scripts.md` loads for PowerShell files. They defer to the repository's `AGENTS.md`. Custom agents do not load steering automatically; a profile must list it in `resources`, which these profiles do not yet do.

## Workflow recipes

Format verified from the Kiro workflow authoring documentation (https://kiro.dev/docs/workflows/authoring/) and from the structure of the existing `ah-project-delivery` recipe: JSON `*.workflow.json` with `name`, `description`, `inputs` and sequential `steps` (`type: step`, `id`, `agent`, `prompt`, `{{previous.output}}`). They are stored in `packages/coding-agent-dispatch/kiro/workflows/`; copy to a project's `.kiro/workflows/` or `%USERPROFILE%\.kiro\workflows\` to use. The installed CLI has no `workflow` subcommand; recipes run through `/workflow run` in a session.

| Recipe | Purpose |
| --- | --- |
| `ah-issue-to-draft-pr` | Linear issue to draft pull request, then `gh pr ready`, then independent review |
| `ah-ci-repair` | Diagnose and fix a red CI run, then recheck |
| `ah-independent-review` | Read-only `ah-reviewer` verdict, checked against the current head |
| `ah-ready-pr-review` | Ready-only review through `packages/coding-agent-dispatch/reviewer` |
| `ah-sentry-rca` | Evidence-first Sentry root cause, read-only |
| `ah-repowise-health` | RepoWise status, refreshed only through the bounded entry point |

Every recipe states: at most three remediation iterations, no merge, release or deploy, no expensive review while the pull request is a draft, a new head commit invalidates an earlier PASS, and the reviewer is never the author. The limit is enforced by prompt text and the recipe's sequential shape, not by a loop construct.

## Not done

- Nothing was installed: `-Apply` was never run against a real profile (only a temporary one in the tests); the real profile was only audited.
- No workflow recipe was executed, and none was validated by Kiro's own validator (the runtime offers `save_workflow_definition`, not `validate_workflow`).
- The IDE was not launched; its version came from install metadata.
- Powers and MCP servers were not changed.
- The interaction between the owner's user-level `all: allow` permissions and these profiles' deny rules was not tested.
- The drift in five installed profiles was not diffed; whether `-Apply` should replace them is an owner decision.
