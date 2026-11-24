# Host details

Read when: choosing a model, a Factory or OpenCode role or a read-only run, dispatching to Cline, OpenCode, Factory, Devin, Warp or Copilot, reviewing Kilo, MiMo or Qwen eligibility, resuming a Cline session, or auditing a host plugin.

Contents: Models, Factory and OpenCode roles, Read-only runs, Account hosts, New plan hosts, Plan routes, Qwen, Factory, Devin, Warp, Cline, OpenCode, Plugin installers.

## Models

Owner direction 2026-11-10: a model or coding plan is allowed on any host where it can be integrated and supported.

- `-Model` is passed through for codex (`-m`), grok (`--model`), opencode, cline, factory, devin, kilo, mimo-code, qwen (`-m`, plus `OPENAI_MODEL` in the child environment). Other hosts take no `-Model`. Warp is retired and dispatch is disabled; it takes no `-Model`.
- `dispatchPolicy.<host>.allowedModels` records the smoke-verified models. It does not limit the choice. An unlisted model adds one stderr line, `note: <host> model '<id>' is not in the smoke-verified list; passing it through`, and the run continues. The host and its plan decide what the model costs; check the cost before routing an expensive one.
- The id must be well formed: no whitespace or shell metacharacters; `provider/model` for opencode, kilo and mimo-code; `provider:model` for cline. A malformed id is refused with exit 3.

Both rules are recorded in `registry/fleet-profile.json` -> `dispatchModelPolicy`.

Subscriptions only, never a pay-as-you-go wallet (owner direction 2026-11-10). These two refusals stay:

- OpenCode: provider `opencode/` is the pay-as-you-go Zen wallet and is refused. Use `opencode-go/<model>`, the Go subscription on the stored Go workspace login.
- MiMo, on every host (kilo `mimo/*`, mimo-code `xiaomi-token-plan-*/*`, qwen's OpenAI-compatible child environment, opencode `mimo-token-plan/*`, cline `mimo-token-plan:*`, and a Codex or Factory model id naming MiMo): the route must be the Xiaomi Token Plan. Provider `xiaomi/` (the pay-as-you-go API in MiMo Code's model listing) is refused. If `MIMO_BASE_URL` is set, its host must be `token-plan-<region>.xiaomimimo.com`; pay-as-you-go is `api.xiaomimimo.com`. If `MIMO_API_KEY` is set, it must start with `tp-` or `ttp-`; pay-as-you-go keys start with `sk-`. On qwen both must be present, because the child environment is that route's only credential. The refusal names the variable and never prints its value.

## Factory and OpenCode roles

`-Role` applies to Factory and OpenCode only. Any other host refuses a role
other than `peer` with exit 3. OpenCode roles map to native V2 agents in
`~/.config/opencode/agents` (see the OpenCode section below).

Factory maps `engineer`, `reviewer` and `tester` through
`dispatchPolicy.factory.roles` to native custom droids in
`~/.factory/droids` (canonical source + installer: see the Factory section
below); a role whose droid file is missing or unmapped is refused with exit 3.
Other roles are refused on Factory.

## Read-only runs

`-ReadOnly` maps to a mode the host enforces, never to prompt wording. A host
qualifies only when the dispatcher has a verified read-only command for it
and `dispatchPolicy.<host>.readOnly` in `registry/fleet-profile.json` records
it. There `readOnly` is an object with `flags` and `omits` when supported,
`false` when checked and absent, and `null` when not established;
`readOnlyNote` holds the dated help text behind each value. Any other host
refuses `-ReadOnly` with exit 3 ("has no enforced read-only mode") and no
writable run starts. `-List -ReadOnly` prints the supported hosts.

| Host | Read-only command |
| --- | --- |
| claude | `--print --permission-mode plan --permission-prompts none` in place of `--permission-mode bypassPermissions` |
| codex | `exec --sandbox read-only --skip-git-repo-check -` |
| factory | `exec` without `--auto`, which is Droid's read-only default |
| qwen | `--approval-mode plan` in place of `--approval-mode yolo` (help 0.27.1: "Analyze only, do not modify files or execute commands") |

`-ReadOnly` cannot be combined with `-SessionId`. No host's read-only mode
has been exercised with a model run; the commands come from each CLI's help
text on 2026-11-11.

## Account hosts

- Cursor Agent, Amp, OpenCode: account login; confirm with the host's own status command before the first dispatch.
- Gemini CLI is retired (2026-11-10) and has no dispatch contract. Dispatch Google work to Antigravity.
- Copilot: runs on the `sh-pendoah` GitHub account; the dispatcher reads that token from gh's keyring into the child environment only.
- Codex reads the task from stdin (`exec --skip-git-repo-check -`) and does not initialize Git. Antigravity gets `--print=<prompt>` after its permissions flag.
- Long, quoted or multiline argument prompts go through a temporary UTF-8 file; the file is removed on completion. OpenCode attaches pointer files with `--file` rather than asking the agent to read outside the checkout, preserving its strict read/glob allowlist.
- Claude's current account eligibility comes from `dispatchPolicy`, not this
  reference. The separate `-HostId claude -AnthropicApiKey` path is a per-call
  opt-in only while its recorded authorization is valid; it is not a fallback
  for an account refusal.

## New plan hosts

Kilo and MiMo Code are dispatchable. `--auto` and `--yolo` approve every action
no rule denies, so each runs only under the policy-named `peer` agent
(`~/.config/kilo/agent/peer.md`, `~/.config/mimocode/agent/peer.md`), whose
rules deny pushes, pull requests, publishing, cloud CLIs and credential reads.
The dispatcher refuses either host when `dispatchPolicy.<host>.agent` is
missing. If a peer file is absent on a machine, recreate it from the rules in
`agentNote` before dispatching; do not run without it.

- Kilo's configured provider/model is `mimo/mimo-v2.6-pro`. Its separately
  authorized Token Plan uses the existing `MIMO_API_KEY` reference, not an
  account login or an authorization for arbitrary API usage.
- MiMo Code's configured plan model is
  `xiaomi-token-plan-sgp/mimo-v2.6-pro`, using its stored plan credential.
- Native skill projections are not portable native plugins. Neither implies
  that a session loaded the skill, that global policy was consumed, or that
  all fleet MCP integrations are available.
- `kilo acp` and `mimo acp` are help-discovered entry points. Protocol
  initialization, session handoff and authenticated inference remain separate
  checks. Do not start a listener or install a bridge to bypass a refused run.

## Qwen

The prompt is passed on stdin, not as an argument: in plan (read-only) mode Qwen refuses to read a prompt file outside the task directory. Smoke-verified 2026-11-11 through the dispatcher on the Token Plan in both the normal and the `-ReadOnly` route; in plan mode a request to create a file wrote nothing. `MIMO_BASE_URL` must be https.

Qwen Code 0.27.1 is dispatchable on the Xiaomi MiMo Token Plan (owner
direction 2026-11-11, SH-4421). The command, from `qwen --help`:

```
qwen --auth-type openai -m <model> --approval-mode yolo -o json <prompt>
```

A positional query is already a one-shot headless run (`-p/--prompt` is
deprecated) and there is no directory flag, so the child's working directory
is the task directory. The stored `~/.qwen` configuration is not used or
written: `--auth-type openai` selects the OpenAI-compatible auth that the
vendor Token Plan page documents, and the credential travels in the child
environment only.

- Auth: `MIMO_API_KEY` and `MIMO_BASE_URL` in the dispatcher's environment
  become `OPENAI_API_KEY`, `OPENAI_BASE_URL` and `OPENAI_MODEL` in the child.
  Both `MIMO_*` variables must be present and plan-shaped (the host pattern
  and `tp-`/`ttp-` key above); a missing or pay-as-you-go value refuses with
  exit 3. `-ShowCommand` prints the child variable names, never the key.
- Default model `mimo-v2.6-pro`, the Token Plan default on the vendor page
  (recorded as page-confirmed, not smoke-verified). `-Model` accepts a bare
  model id and is copied into `-m` and `OPENAI_MODEL`.
- Scrub: the parent's `OPENAI_API_KEY`/`OPENAI_BASE_URL`/`OPENAI_MODEL` are
  removed before the child values are set, and `ANTHROPIC_*`, `GEMINI`,
  `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`, `DASHSCOPE_API_KEY`,
  `MODELSCOPE_API_KEY`, `QWEN_API_KEY`, `GH_TOKEN` and `GITHUB_TOKEN` are
  dropped so a stray provider variable cannot retarget auth or billing.
- Qwen has no agent-profile denylist, so `--approval-mode yolo` approves
  every tool call. The child carries the same guard as warp: `GIT_CONFIG_*`
  push rewrites to an unhandled scheme, an empty `GH_CONFIG_DIR`, and no
  GitHub tokens. It is not a shell denylist; run qwen only in worktrees.
- `qwen auth` is a removed command and `qwen -p` under the stored
  `selectedType nvidia` settings crashed in `resolveModelConfig` on
  2026-11-10; the route was assembled from help and the vendor page and has
  not been exercised with a model run. Do not change its stored credentials
  to make a check pass: the route's plan variables live in the dispatcher's
  environment, and the child never reads the saved configuration.

## Plan routes

Factory smokes re-verified 2026-11-14 (SH-4676) through `Invoke-CodingAgent.ps1` (`READY`, exit 0, `factory_credits: 0`); opencode/kilo columns verified 2026-11-14. Keys come from environment variables only.

| Plan | Variable | opencode | kilo | factory |
| --- | --- | --- | --- | --- |
| Qwen Token Plan | `QWEN_TOKEN_PLAN_API_KEY` | `qwen-token-plan/qwen3.8-max`, `qwen-token-plan/qwen4-max-preview` | `qwen-token-plan/qwen3.8-max` | `custom:qwen3.8-max-tp`, `custom:qwen4-max-preview` |
| Z.ai GLM Coding Plan | `ZAI_CODING_PLAN_API_KEY` | `zai-glm-plan/glm-5.3` (native), `zai-coding-plan/glm-5.3` (legacy launcher) | `zai-coding-plan/glm-5.3` | `custom:glm-5.3-zai` |
| MiMo Token Plan | `MIMO_API_KEY` | `mimo-token-plan/mimo-v2.6-pro` | `mimo/mimo-v2.6-pro` | `custom:mimo-v2.6-pro`, `custom:mimo-v2.6-flash` |

- A Factory `custom:` id is `custom:` + the BYOK entry's `model` field in `~/.factory/settings.json`, stable under reordering (droid 1.10.0/1.12.1; the earlier "array index suffix" claim was wrong). The canonical entries are reproducible from AgentHub: `packages/coding-agent-dispatch/factory/custom-models.json` + `Install-FactoryCustomModels.ps1` (audit/apply, `${ENV}` key references only, owner-authored entries untouched).
- A BYOK entry whose `model` field collides with a Factory built-in id (`qwen3.8-max`, `glm-5.3`) gets accounted at the built-in multiplier even though inference goes to the BYOK endpoint; the canonical entries therefore use renamed ids with `extraArgs.model` carrying the real upstream name. Detail: `dispatchPolicy.factory.byokCreditsNote` in `registry/fleet-profile.json`.
- Qwen Token Plan terms allow AI coding tools only; never call its endpoint from scripts or app backends.
- Endpoints (Token Plan only; pay-as-you-go endpoints and `sk-` keys are never used): Qwen `https://token-plan.maas.qwencloudapi.com/compatible-mode/v1` (Anthropic route `/apps/anthropic`); MiMo Singapore `https://token-plan-sgp.xiaomimimo.com/v1` (Anthropic route `/anthropic`). Qwen models that passed: `qwen4-max-preview` (default for coding), `qwen3.8-max`, `qwen3.8-flash`. The Qwen `auto` model is refused on the Anthropic route that opencode and kilo can use (`auto does not support parameter(s): tool_choice`); name a model. Discount windows are in the global policy.
- MiMo models: `mimo-v2.6-pro` (default), `mimo-v2.6-flash`. MiMo Desktop is a GUI application with no unattended contract and is not a dispatch route.
- `custom:glm-5.3-zai` could not complete its READY smoke on 2026-11-14: the Z.ai Coding Plan returned 429 (5-hour limit, reset 2026-11-15 08:24 local) with `factory_credits: 0`, which proves routing but not a completion.

## Factory

Dispatch is governed. `exec --auto` runs at low or medium only (`high` permits git push; `--skip-permissions-unsafe` is never emitted). `-o json` returns a session id and credit usage. `-m` defaults to `dispatchPolicy.factory.model` (a zero-credit BYOK plan route since SH-4676; Factory-hosted ids in `allowedModels` spend credits); `-Model` passes any well-formed model id through (see Models). `--settings` points at `factory/runtime-settings.json`, checked with `droid rules check` (extract its `permissionRules` object first: `--file` wants a standalone `{version, rules}` file); it also pins `subagentModelSettings` light/medium/heavy to `inherit` so any subagent of a dispatched run stays on the parent's subscription route instead of the hosted `lightModel`.

Roles (`-Role engineer|reviewer|tester`) run as native custom droids through one Task-tool delegation, mapped by `dispatchPolicy.factory.roles`. Canonical droids live in `packages/coding-agent-dispatch/factory/droids` (`ah-engineer`, `ah-reviewer` read-only, `ah-browser-tester` on the droid-control skill's agent-browser atom) and deploy to `~/.factory/droids` with `Install-FactoryDroids.ps1`. Exec sessions block the Task tool by default and `--add-tools Task` does not unblock it, so a role run passes an explicit `--only-tools` union naming Task; that union is the session ceiling and each droid's frontmatter narrows inside it. `-ReadOnly` is refused for writing roles; `-ReadOnly -Role reviewer` additionally verifies from the droid's frontmatter that its tools are read-only. Third-party Claude-format plugins whose hooks use POSIX `sh` or `%CLAUDE_PLUGIN_ROOT%` break every Execute call on Windows (observed with `aws-core@claude-plugins-official`; disabled 2026-11-14, re-enable only with a Windows-safe hook).

## Devin

Devin is a retained, first-class fleet agent (SH-4969, owner direction 2026-11-19). It has three lanes.

**Local CLI (`-HostId devin`).** `devin -p --prompt-file` with the flags in `launchDefaults.devin`, never `--cloud`; a missing `launchDefaults.devin` refuses. `--model` defaults to `dispatchPolicy.devin.model`; `-Model` passes any well-formed model id through (see Models). Permission mode is `dangerous` by owner direction and Windows has no Devin sandbox, so run Devin only in `C:/wt` worktrees. The child loses `DEVIN_API_KEY`, `DEVIN_API_TOKEN`, `DEVIN_SERVICE_USER_TOKEN` and `DEVIN_ORG_ID` so the CLI's stored account login is used. `process_model: daemon` is set in `%APPDATA%\devin\config.json` (observed 2026-11-19); after Devin Desktop restarts, `devin -r <session-id> -p "<message>"` messages a session Desktop has open.

**Devin Cloud (`-HostId devin-cloud`, or the adapter directly).** `Invoke-CodingAgent.ps1 -HostId devin-cloud -PromptFile <brief> -Cwd <repo> [-RunId <id>] [-MaxAcu <n>] [-Repo owner/name] [-SchemaFile <schema.json>] [-Title <t>]` calls `Invoke-DevinCloud.ps1 -Action create`, which POSTs `{apiBase}/organizations/{orgId}/sessions` ([v3 API](https://docs.devin.ai/api-reference/v3/overview)). Steer and collect with the adapter: `-Action status|wait|messages|message|stop|list -SessionId <id>`. Every call prints one JSON object.

- Spend guard: every create carries `max_acu_limit`, default `cloudBudgetAuthorization.defaultMaxAcuLimit` (10). Raise it for one task with `-MaxAcu <n>` only when the task authorizes it. `-MaxAcu` must be a positive whole number; `2.5`, `1e3` or `abc` refuse with exit 3.
- Concurrency: a create is refused (exit 3) while 3 sessions tagged `agenthub` are `new`, `claimed`, `running` or `resuming`. The count reads every page; if it cannot complete (an API error, or a page promising more with no cursor) the create is refused with exit 3 (fail closed). The v3 list has no status filter, so status is filtered client-side.
- Dedupe: sessions are tagged `agenthub` and `run:<RunId>`; a create whose run tag already exists returns that session (`deduplicated: true`, with no `max_acu_limit` field because the v3 session response does not carry one), because v3 has no idempotency key. Without `-RunId` the run id is `auto-` plus a hash of the prompt, the sorted repos and the title, so an identical re-dispatch dedupes; only an explicit `-RunId` starts a new run for the same task.
- Race safety: the dedupe lookup, the concurrency count and the POST run under the machine-wide mutex `Global\AgentHub-DevinCloud-Create` (bounded wait 120 s, then exit 3).
- `wait` polls with backoff until `status_detail` is `finished`, `status` is `exit`, `error` or `suspended`, or Devin is `waiting_for_user` or `waiting_for_approval` (answer with `-Action message`). It retries a 429, a 5xx or a transport timeout with bounded backoff (six in a row, within `-TimeoutSec`). It reports `acus_consumed`, `pull_requests` and `structured_output`. Exit codes: 0 when finished, waiting on a person, or exited at a user's request; exit 4 on timeout, `suspended`, `error`, or `exit` with any other detail; 1 on a non-retryable API failure; 3 on a refusal.
- After answering, pass the cutoff that `-Action message` prints: `-Action wait -SessionId <id> -After <cutoff>` (a message `created_at`, or `cutoff_event_id`). With `-After`, a `waiting_for_user` or `waiting_for_approval` that was already showing counts only after Devin posts a new message or the status changes, so the wait does not return on the stale state.
- Key: `op read` of `cloudBudgetAuthorization.keyOpRef` through the 1Password service account (`OP_SERVICE_ACCOUNT_TOKEN`), held in memory only. The reference uses vault and item ids because `op read` rejects `&` (vault "Business & Apps", item "Devin Cloud API service user"). `DEVIN_CLOUD_API_KEY` is an in-process override only: the dispatcher removes it from every child it starts and hands it only to the adapter, which consumes it before starting `git` or `op`; a value persisted in the User or Machine environment is refused with exit 3. A missing `op`, token or item refuses with exit 3. HTTP calls run with debug and verbose output silenced, and any printed key is masked to its last four characters. The service user is `agenthub-dispatch` (Member); its key expires 2027-02-17.
- No read-only mode: `-ReadOnly`, `-Model`, `-Role` and `-SessionId` are refused.

The official [Devin MCP server](https://docs.devin.ai/work-with-devin/devin-mcp) (`https://mcp.devin.ai/mcp`, registry id `devin`) is the same cloud lane from inside a host: sessions, playbooks, knowledge, Devin Review and DeepWiki. It authenticates through `Get-DevinMcpHeaders.ps1`, a native headers helper that runs `op read` at connect time and prints `Authorization` and `X-Org-Id`; no host config holds the key. It is declared for Claude only and is owner-configured (the sync does not write `headersHelper`). The MCP client receives the raw key, so the ACU cap and the concurrency cap are enforced only by the dispatcher adapter, not on this lane: a session created through `devin_session_create` must pass `max_acu_limit` 10 and the `agenthub` tag by convention. Beyond that, the documented Devin-side controls are [organization-level ACU limits](https://docs.devin.ai/admin/billing/org-acu-limits) and [user-level ACU limits](https://docs.devin.ai/admin/billing/user-acu-limits), both monthly caps, and the v3 Organization `max_session_acu_limit` field, a per-session limit on the organization. The owner has not yet set an org-level per-session limit. Nothing in AgentHub enforces any of these on that lane.

**Linear.** Assign the ticket to Devin (or add a Devin skill label, or @mention Devin in a comment) and Devin starts a cloud session that streams its activity, plan and pull request back into the issue ([Linear integration](https://docs.devin.ai/integrations/linear)).

**GitHub.** On an open pull request in a connected repository, a comment starting `/devin <prompt>` goes to the session already working on that PR, or starts one; `/devin review` starts a Devin Review ([GitHub integration](https://docs.devin.ai/integrations/gh)). `devin --cloud -r <id>` reopens any cloud session in the terminal ([CLI cloud](https://docs.devin.ai/cli/cloud)); dispatch never runs `--cloud` itself.

## Warp

The child sets `WARP_CLI_MODE=1` and never opens the terminal GUI. A recorded `dispatchPolicy.warp.mcpConfig` is passed as `--mcp` with `--mcp-startup-timeout 30s` after resolving its `{userHome}` template; a missing file skips both flags with one stderr warning, and the file is never read or printed. Keep Warp enabled only while an account-status command and a local-only mode are both verified.

## Cline

Cline dispatch is enabled in `dispatchPolicy`:

- Uses the saved provider settings in the private Cline profile (keys stay there), `--json` execution, low thinking and the dispatcher timeout. Native skills, plugins and MCP are retained. Do not use `--yolo`.
- Resume: `-HostId cline -SessionId <id>` uses ACP `session/load` (the `--id` flag forces interactive mode). It starts a windowless ACP child after the normal gates, keeps task text on stdin, cancels permission requests (tasks needing permission can stop early), stops its child tree on completion, and returns JSON with `sessionId`, `text` and `stopReason`. Other hosts refuse `-SessionId`. A live resumed prompt is unverified.
- `cline --acp` is an on-demand stdio ACP agent. The ACP client owns permission handling; keep `--auto-approve false` unless the task authorizes otherwise. Do not install an A2A/AMCP bridge or invent a Codex ACP setting.
- `cline/acp-session.mjs` is a transport-only client for caller-owned streams.

## OpenCode

The Go subscription is provider `opencode-go`; the default is `opencode-go/glm-5.3-flash`. Provider `opencode` is the pay-as-you-go Zen wallet and is refused (see Models).

`-Role engineer|reviewer|tester|researcher` runs the matching native V2 agent
from `~/.config/opencode/agents` (canonical copies in
`packages/coding-agent-dispatch/opencode/agents`, recorded in
`dispatchPolicy.opencode.roles`); a role the policy does not record or whose
agent file is missing from the installed home is refused. Without `-Role` the
run keeps the guarded `peer` agent. `-ReadOnly` always runs the `readonly`
agent (`roles.readonly`) — never `peer` — and is refused unless the installed
`readonly.md` ordered frontmatter permissions deny every action by default and
allow only `read` and `glob`, with secret and auth-file reads denied. `-Role
reviewer` uses the same gate for its installed `reviewer.md` profile. The
dispatcher parses the rules (last match wins), so body text cannot satisfy the
gate. Restricted child processes set `OPENCODE_DISABLE_PROJECT_CONFIG=true`
and `OPENCODE_PURE=true`, preventing repository configuration/instructions and
external plugins from changing the effective policy.
Live-verified on opencode 2.3.0 (2026-11-14): the profile-filtered session
exposed no write/edit/patch tools and the prompted probe file was never
created. Combining `-ReadOnly` with a writing role is refused.

On Windows, `-HostId opencode -Model zai-coding-plan/glm-5.3` uses the
installed `%LOCALAPPDATA%/AgentHub/zai/opencode-zai.ps1` launcher and its
separate OpenCode 1.x settings. It exposes the Z.ai MCPs and workspace
read/edit/search tools. Shell, subagents and access outside the workspace are
denied for these headless runs. Use a different route for tasks requiring a
shell. The launcher must pass through the OpenCode exit code. The launcher has
no V2 agent profiles: it refuses every `-Role` except peer and any `-ReadOnly`.

`opencode acp` is the native stdio ACP server, sharing the persisted account and configuration. The ACP client owns permission handling.

## Plugin installers

Each installer audits by default and changes files only with `-Apply`. None starts a host, registers background maintenance, or changes credentials. Re-audit after a host update.

| Script | Purpose |
| --- | --- |
| `Install-OpenCodeToolDiscovery.ps1` | Native global plugin that defers schemas and skill/MCP catalogs until needed. Reload the shared OpenCode service after installing. |
| `Install-OpenCodeProfiles.ps1` (in `packages/coding-agent-dispatch/opencode/`) | Deploys the canonical V2 agent profiles (`peer`, `engineer`, `reviewer`, `tester`, `researcher`) to `~/.config/opencode/agents`. Hash-verified `-Apply` repairs drift, never touches owner-authored agents, `opencode.json`, MCP files, plugins or credentials, and writes no backups. |
| `Install-ClineToolDiscovery.ps1` | Installs `cline/lightweight-chat.js` (`find_tools` loads up to five tools per search) for the `qwen3.8-max` profile, and sets Cline's global `compactionEnabled` to `false`, because compaction otherwise estimates the full tool catalog and can discard tool results. Verify a plain reply and a real file read after a Cline upgrade. |
| `Install-ClinePeerGuard.ps1` | Installs `~/.cline/plugins/peer-guard.js`, a deny list (not a sandbox) active only when `AGENTHUB_PEER_GUARD=1` and `CLINE_SESSION_BACKEND_MODE=local`; it fails open in hub mode. Blocks git push, reset --hard, clean -f, mutating gh, publish, cloud CLIs, scheduled tasks and services, host administration, credential dumps, disk and power operations, recursive root/home deletes, and writes to protected paths. |
