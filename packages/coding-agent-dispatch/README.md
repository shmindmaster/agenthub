# coding-agent-dispatch

Version 0.8.14 (the root `plugin.json` is the single version authority; `SKILL.md`
metadata and every host projection carry the same number and
`tests/validate-dispatch.ps1` enforces parity). The package is a full plugin:
`.claude-plugin`, `.codex-plugin`, `.cursor-plugin`, `.devin-plugin` and
`.antigravity-plugin` projections, an empty `.mcp.json`, and catalog entries in
`.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.

Windowless runner so one coding agent can call another. Claude and Codex are
the primary orchestrators. The callable set is whatever
`Invoke-CodingAgent.ps1 -List` prints. Flags are the ones verified against
the installed CLIs on 2026-10-21. A host without that evidence is refused,
including every GUI.

Verified local command contracts: Claude, Codex, Cursor Agent, Grok,
OpenCode, Antigravity CLI, Factory Droid, Cline, Copilot, Amp, Devin
and Warp/Oz. `cursor` routes to Cursor Agent; its account-mode smoke returned
`ok` on 2026-10-22. Amp's account-mode smoke returned `ok` with MCP servers
disabled for dispatch. Gemini CLI was retired on 2026-11-10 and has no
contract; Google work goes to Antigravity CLI. `windsurf`
routes to Devin. Readiness is additionally gated by
`dispatchPolicy` and each host's autonomy profile. Devin uses its paid plan
model recorded in `registry/fleet-profile.json`; OpenCode's Go model is
selected there as `opencode-go/<model>`, the Go subscription provider.
OpenCode 2.1.4 native Console account OAuth and Go-only
inference passed on 2026-10-23 without an API-key override. Its CLI and Desktop
share the native service; `run` uses the child process working directory.
Windsurf shares Devin's model and command. Current host readiness is recorded
in `registry/fleet-profile.json`; detailed runtime output stays outside this
public repository.

Cline uses normal JSON execution with its saved provider/model, low thinking,
native timeout, plugins and MCP rather than the restricted `--yolo` benchmark
toolset. The dispatcher starts bounded new tasks by default. For existing
Cline history, pass `-HostId cline -SessionId <id> -Prompt <task>`; this
uses ACP `session/load` and awaits the new reply. Cline 3.0.73's `--id` is
interactive-only. ACP loading and Desktop attachment previously passed a
synthetic history check. An ACP client launches
`cline --acp` on demand. No A2A bridge or background listener is enabled by this
capability; concurrent hosts run under separate claims with non-overlapping write
scopes. The owner's authorized Alibaba Coding Plan
settings stay in the private Cline profile, never in the registry. OpenCode
2.1.4 also passed native ACP initialization and synthetic session creation,
listing and loading. Its on-demand private backend shares persisted account
and configuration; an ACP client is still required for protocol handoff.

`cline/acp-session.mjs` supplies the transport-only resume client: it awaits
`initialize`, `session/load`, then `session/prompt`, collects the new assistant
reply without replayed history, bounds requests, and cancels permission
requests. Its stream tests launch no host. It does not enable Cline dispatch:
`dispatchPolicy` in `registry/fleet-profile.json` decides which hosts may run agent work.
`cline/acp-dispatch.mjs` connects this client to a windowless, on-demand
`cline --acp --auto-approve false` child. Session and task text travel over
stdin, permissions are cancelled, and only the owned child tree is stopped.
The dispatcher retains its policy and autonomy gates and outer timeout.
Offline tests cover the full dispatcher with a synthetic ACP executable;
live Cline resume remains unverified under the current restriction.

The optional Cline Qwen tool-discovery plugin is maintained in this package's
`skills/dispatch/cline/lightweight-chat.js`. It uses documented SDK
hooks to send only `find_tools` initially, loads a bounded selection when needed,
and resets the selection for each user turn. Native tool implementations and
approval choices remain intact. CLI 3.0.73 and Desktop 0.0.48 passed actual
plain-chat and tool-discovery checks. This is separate from the VS Code extension.
`Install-ClineToolDiscovery.ps1` audits by default; `-Apply` repairs only that
file in the private Cline user directory, with hash readback. AgentHub skill
sync supplies its canonical source and repair command; installation is explicit.
It never starts Cline or registers background maintenance. User configuration
lives outside the application installation and normally survives updates;
future SDK compatibility still requires verification after an upgrade.

The optional Cline peer guard plugin is maintained in this package's
`skills/dispatch/cline/peer-guard.js`. It uses the Cline SDK `beforeTool`
hook to block a deny-list of dangerous commands when running unattended with
`--auto-approve true`. The guard activates only when the launcher sets
`AGENTHUB_PEER_GUARD=1` and the session runs in-process (`CLINE_SESSION_BACKEND_MODE=local`);
in hub mode the variable never reaches the plugin, so it fails open. It is a deny list,
not a sandbox: it blocks git push, git reset --hard, git clean -f, gh mutating
operations, npm/pnpm publish, cloud CLIs (az, aws, gcloud, terraform, etc.),
scheduled task/service creation, agent host administration (cline, opencode, codex
auth), credential dumps, disk/power operations, recursive root/home deletes,
and writes to protected paths (D:\Local-AI runtime, ~/.cline/data/settings,
~/.codex/auth). Allowed developer commands (git status/commit with "push" in
message, gh pr view/diff/api GET, npm/pnpm test/build, npx playwright test,
Remove-Item of relative build dirs, git branch -d) are not blocked.
`Install-ClinePeerGuard.ps1` audits by default; `-Apply` copies the package file
to `~/.cline/plugins/peer-guard.js` with hash readback. It never starts Cline or
registers background maintenance.

OpenCode 2.1.4 has the equivalent native plugin in
`skills/dispatch/opencode/lightweight-chat.js`. It defers tool schemas,
skill descriptions and MCP instructions until `find_tools` selects them, then
resets that selection on each user turn. `Install-OpenCodeToolDiscovery.ps1`
audits by default; `-Apply` installs and verifies the single global plugin file.
It does not change permissions, credentials or the provider. CLI and Desktop
consume the shared service; a running service needs native `opencode reload`
after installation. Test discovery again after an SDK upgrade. Neither repair
command installs a scheduled job. See `docs/fleet/context-reduction.md`.

Account-based authentication is recorded per CLI in `registry/fleet-profile.json`
-> `hostSettings`. The dispatcher removes
host-specific API-key environment variables from account-authenticated
children. OpenCode's private provider settings pin the Go-only endpoint;
Console account OAuth is stored by the native service. Follow the owner-only checklist at
`docs/fleet/account-logins-2026-10-21.md`; do not log in or accept paid fallback
automatically. Other gated CLIs need verified included allowance or an explicit
task credit budget and one smoke before enabling. Model catalogs and help
output alone do not prove working inference.

`-HostId claude -AnthropicApiKey` is a per-call opt-in (owner direction
2026-10-24) that keeps `ANTHROPIC_API_KEY` for that one run while
`dispatchPolicy.claude` stays disabled. It requires
`dispatchPolicy.claude.apiKeyOptIn`, refuses after its `expiresUtc`, passes its
`model` unless `-Model` is given, and is refused for every other host. The key
is shared promotional credit; the skill documents when to use it.

`-Model` chooses the model per task for codex, grok, opencode, cline, warp,
factory, devin, kilo, mimo-code, qwen and kiro. Owner direction 2026-11-10: a model
or coding plan is allowed on any host where it can be integrated and
supported. `dispatchPolicy.<host>.allowedModels` records the smoke-verified
models and does not limit the choice; an unlisted model is passed through with
one stderr note. The dispatcher refuses only a malformed id (whitespace, shell
metacharacters, or a missing `provider/model` or `provider:model` shape where
the host needs one) and the two subscription-only cases below.

Subscriptions only, never a pay-as-you-go wallet (owner direction 2026-11-10).
OpenCode provider `opencode/` is the Zen wallet and is refused; use
`opencode-go/<model>`. A MiMo-routed model on any host must run on the Xiaomi
Token Plan: provider `xiaomi/` is refused, `MIMO_BASE_URL`, when set, must name
a `token-plan-<region>.xiaomimimo.com` host, and `MIMO_API_KEY`, when set, must
start with `tp-` or `ttp-` — on qwen both must be present, since the child
environment is that route's only credential. A refusal names the variable and
never prints its value. Details are in `skills/dispatch/references/hosts.md`.

`-HostId qwen` (SH-4421) runs Qwen Code 0.27.1 headless on that plan:
`qwen --auth-type openai -m <model> --approval-mode yolo -o json <prompt>`
with the task directory as the child's working directory (qwen has no
directory flag). `MIMO_API_KEY` and `MIMO_BASE_URL` become `OPENAI_API_KEY`,
`OPENAI_BASE_URL` and `OPENAI_MODEL` in the child; the parent's `OPENAI_*`
and the other providers' keys (`ANTHROPIC_*`, `GEMINI`, `GOOGLE_*`,
`DASHSCOPE_API_KEY`, `QWEN_API_KEY`, `MODELSCOPE_API_KEY`, GitHub tokens) are
scrubbed first so a stray variable cannot retarget billing. The default model
is `mimo-v2.6-pro`, confirmed on the vendor Token Plan page, not
smoke-verified. The stored `~/.qwen` configuration is neither read nor
written; `-ShowCommand` prints the child variable names, never the key. As
with warp, yolo mode has no agent-profile denylist, so the child carries the
`GIT_CONFIG_*`/`GH_CONFIG_DIR` push guard.

`-Role` (SH-4418) picks a Kiro profile: `peer`, the default, keeps the guarded
`ah-peer` command; `engineer`, `reviewer`, `tester`, `architect` and `incident`
run the V3 engine on `ah-<role>` from `kiro/agents/`, recorded in
`dispatchPolicy.kiro.roles`. A role whose profile is missing from
`~/.kiro/agents` is refused, and so is a role other than `peer` on any other
host.

`-ReadOnly` runs a host in a read-only mode the host itself enforces, never
through prompt wording: claude (`--permission-mode plan`), codex
(`--sandbox read-only`), factory (`exec` without `--auto`), kiro (the
`ah-readonly` profile) and qwen (`--approval-mode plan` in place of `yolo`).
`dispatchPolicy.<host>.readOnly` records the flags, or
`false` (checked, none) or `null` (not established), with the dated help text
in `readOnlyNote`. Every other host refuses `-ReadOnly` with exit 3; there is
no fallback to a writable run. `-List -ReadOnly` prints the supported hosts.
No read-only mode has been exercised with a model run.

Codex accepts non-repository working directories without creating Git state.
Antigravity uses attached `--print=<prompt>`. Long or shell-sensitive argument
prompts use temporary UTF-8 task files. Children, including batch shims and
timeout cleanup, run hidden. No cloud adapter, login or scheduled task is
created. Hosted cloud aliases are explicitly refused.

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\skills\dispatch\Invoke-CodingAgent.ps1 -List
```

Deployment is a separate gate. Audit the fleet rows with
`Sync-Plugins.ps1 -RepositoryRoot <repo> -UserProfile <profile> -PluginId coding-agent-dispatch -Json`
and install onto hosts with the same command plus `-Apply` once the audit is
clean; `-Apply` deploys the published source into host caches and requires
the clean published main checkout and green CI (pushing the commit is what
publishes). Kilo, MiMo Code and
Qwen Code receive skills as host-local junctions under
`~/.kilocode/skills`, `~/.mimocode/skills` and `~/.qwen/skills` -- a native skill projection,
not an `ah-*` plugin. `cursor-agent` and `vscode-insiders` declare
`nativeOwnerHost`, so their rows observe the Cursor local plugin and the
Copilot marketplace install instead of installing twice. The shared
`~/.agents/skills` library stays empty.

`agents/claude/coding-agent.md` and `agents/codex/coding-agent.toml` are the
orchestrator agent definitions, referenced by each host manifest. Installing
the plugin places them; no manual copy is needed. Sync-Subagents does not
own those two files.

`tests/Test-CodingAgentDispatch.ps1` uses synthetic native argument recorders
and never consumes a model run. It covers the command fixes, new hosts,
model pass-through, malformed-id and subscription-only refusals, Kiro roles,
the enforced read-only mode and its refusals,
Unicode/multiline transport, alias policy gates, missing binaries and bounded
hidden process-tree termination. `-DispatcherPath` can demonstrate regression
failures against an older copy without changing installed hosts.

## reviewer/ — the ready-only independent PR reviewer (SH-4416)

`reviewer/Invoke-PrReview.ps1` reviews one pull request through this
package's dispatcher on a host different from the one that authored the PR
(branch prefix or a `[host: <id>]` PR-body marker). The script issues no
write command, and the model run is host-enforced read-only on claude,
codex, factory, kiro and qwen: every dispatcher call carries `-ReadOnly` (and
`-Role reviewer` on Kiro), the reviewer host is chosen only among hosts
whose `dispatchPolicy.<host>.readOnly` in `registry/fleet-profile.json`
records an enforced read-only mode, and the run ends BLOCKED, with no model
run, when none is available. The reviewer also fences the pull request's
text as data with a per-run delimiter, withholds GitHub tokens and
`*_API_KEY` / `*_TOKEN` / `*_SECRET` variables from the dispatcher process
and runs it in an empty temporary directory. Automatic triggering is still
not wired (SH-4411). Review markers are trusted only at the start of a comment authored
by the reviewer's own GitHub login (`gh api user` or `-ReviewerLogin`). It refuses a
draft (exit 3), skips a head SHA that already carries a review verdict unless
`-Force`, never reviews on `synchronize`, retries a malformed answer once and
then reports BLOCKED, and never approves, merges, pushes or edits. It posts
at most one bounded summary comment carrying a hidden idempotence marker, and
only with `-Post`. The owner keeps merge control.

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\reviewer\Invoke-PrReview.ps1 `
  -Repo shmindmaster/agenthub -Pr 110 -Trigger ready_for_review -Post
pwsh -NoProfile -File .\packages\coding-agent-dispatch\reviewer\Invoke-PrReview.ps1 `
  -Repo shmindmaster/agenthub -Pr 110 -Status
```

The review brief carries the PR title/body, linked issue ids, the
base-to-head diff (bounded at 50000 characters per file group, 8 groups,
with everything beyond that reported as not covered), the repo's `AGENTS.md`
at the reviewed head, and the reviewer instructions in
`packages/product/agents/reviewer.agent.md`. Subscription routes only: the
model choice is passed to the dispatcher, which enforces the
subscription-only refusals. `tests/Test-PrReview.ps1` runs the whole
behavior with a stubbed `gh` and dispatcher — no network, no model run.
How this will later be triggered (GitHub `pull_request` `ready_for_review`
through AWS CodeBuild, SH-4411), rollback and the run instructions are in
`docs/runbooks/pr-review.md`.
