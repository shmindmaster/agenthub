# Host details

Read when: choosing a model, a Kiro role or a read-only run, dispatching to Cline, OpenCode, Factory, Devin, Warp or Copilot, reviewing Kilo or MiMo eligibility, resuming a Cline session, or auditing a host plugin.

Contents: Models, Kiro roles, Read-only runs, Account hosts, New plan hosts, Factory, Devin, Warp, Cline, OpenCode, Plugin installers.

## Models

Owner direction 2026-11-10: a model or coding plan is allowed on any host where it can be integrated and supported.

- `-Model` is passed through for codex (`-m`), grok (`--model`), opencode, cline, warp, factory, devin, kilo, mimo-code and kiro. Other hosts take no `-Model`.
- `dispatchPolicy.<host>.allowedModels` records the smoke-verified models. It does not limit the choice. An unlisted model adds one stderr line, `note: <host> model '<id>' is not in the smoke-verified list; passing it through`, and the run continues. The host and its plan decide what the model costs; check the cost before routing an expensive one.
- The id must be well formed: no whitespace or shell metacharacters; `provider/model` for opencode, kilo and mimo-code; `provider:model` for cline. A malformed id is refused with exit 3.

Both rules are recorded in `registry/fleet-profile.json` -> `dispatchModelPolicy`.

Subscriptions only, never a pay-as-you-go wallet (owner direction 2026-11-10). These two refusals stay:

- OpenCode: provider `opencode/` is the pay-as-you-go Zen wallet and is refused. Use `opencode-go/<model>`, the Go subscription on the stored Go workspace login.
- MiMo, on every host (kilo `mimo/*`, mimo-code `xiaomi-token-plan-*/*`, opencode `mimo-token-plan/*`, cline `mimo-token-plan:*`, and a Codex or Factory model id naming MiMo): the route must be the Xiaomi Token Plan. Provider `xiaomi/` (the pay-as-you-go API in MiMo Code's model listing) is refused. If `MIMO_BASE_URL` is set, its host must be `token-plan-<region>.xiaomimimo.com`; pay-as-you-go is `api.xiaomimimo.com`. If `MIMO_API_KEY` is set, it must start with `tp-` or `ttp-`; pay-as-you-go keys start with `sk-`. The refusal names the variable and never prints its value.

## Kiro roles

`-Role` applies to Kiro only. Any other host refuses a role other than `peer`
with exit 3.

| Role | Profile | Command |
| --- | --- | --- |
| `peer` (default) | `dispatchPolicy.kiro.agent` (`ah-peer`) | `kiro-cli chat --no-interactive --trust-all-tools --agent ah-peer --model <m> <prompt>` |
| `engineer`, `reviewer`, `tester`, `architect`, `incident` | `dispatchPolicy.kiro.roles.<role>` (`ah-<role>`) | `kiro-cli chat --v3 --no-interactive --trust-all-tools --agent ah-<role> --model <m> <prompt>` |

The role profiles are `packages/coding-agent-dispatch/kiro/agents/ah-<role>.json`.
A role is refused with exit 3 when its profile file is missing from
`~/.kiro/agents` or when `dispatchPolicy.kiro.roles` does not name it. The
dispatcher does not install profiles.

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
| kiro | `chat --v3 --no-interactive --trust-all-tools --agent ah-reviewer`: the reviewer profile has no write tool and denies `fs_write` and outward shell commands |

Kiro notes: `-ReadOnly` always runs the reviewer profile, so it is refused
with `-Role engineer`, `tester`, `architect` or `incident`. It is also
refused when the installed `~/.kiro/agents/ah-reviewer.json` is missing or
lists a write tool. The profile keeps the shell tool for running checks, so
this is a profile guard and not an operating-system sandbox.

`-ReadOnly` cannot be combined with `-SessionId`. No host's read-only mode
has been exercised with a model run; the commands come from each CLI's help
text on 2026-11-11.

## Account hosts

- Cursor Agent, Amp, OpenCode: account login; confirm with the host's own status command before the first dispatch.
- Gemini CLI is retired (2026-11-10) and has no dispatch contract. Dispatch Google work to Antigravity.
- Copilot: runs on the `sh-pendoah` GitHub account; the dispatcher reads that token from gh's keyring into the child environment only.
- Codex reads the task from stdin (`exec --skip-git-repo-check -`) and does not initialize Git. Antigravity gets `--print=<prompt>` after its permissions flag.
- Long, quoted or multiline argument prompts go through a temporary UTF-8 file and a short pointer; the file is removed on completion.
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

Kiro CLI is dispatchable on its Builder ID login. `--trust-all-tools` approves
every tool call, so it runs only under the policy-named `ah-peer` agent
(`~/.kiro/agents/ah-peer.json`), which denies outward and destructive commands
and does not load the host's MCP file. Every Kiro model spends plan credits at
its own multiplier; any model Kiro offers may be routed with `-Model`. The Kiro
IDE and KiroCrew are not dispatch targets.

Qwen has a saved configuration, but its observed run failed in
`resolveModelConfig`. Do not describe it as callable or change its credentials
to make a check pass.

## Factory

Dispatch is governed. `exec --auto` runs at low or medium only (`high` permits git push; `--skip-permissions-unsafe` is never emitted). `-o json` returns a session id and credit usage. `-m` defaults to `dispatchPolicy.factory.model`; `-Model` passes any well-formed model id through (see Models). `--settings` points at `factory/runtime-settings.json`, checked with `droid rules check`.

## Devin

Local only: `devin -p --prompt-file`, never `--cloud`. `--model` defaults to `dispatchPolicy.devin.model`; `-Model` passes any well-formed model id through (see Models). Permission mode is `dangerous` by owner direction and Windows has no Devin sandbox, so run Devin only in `C:/wt` worktrees.

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

`opencode acp` is the native stdio ACP server, sharing the persisted account and configuration. The ACP client owns permission handling.

## Plugin installers

Each installer audits by default and changes files only with `-Apply`. None starts a host, registers background maintenance, or changes credentials. Re-audit after a host update.

| Script | Purpose |
| --- | --- |
| `Install-OpenCodeToolDiscovery.ps1` | Native global plugin that defers schemas and skill/MCP catalogs until needed. Reload the shared OpenCode service after installing. |
| `Install-ClineToolDiscovery.ps1` | Installs `cline/lightweight-chat.js` (`find_tools` loads up to five tools per search) for the `qwen3.8-max` profile, and sets Cline's global `compactionEnabled` to `false`, because compaction otherwise estimates the full tool catalog and can discard tool results. Verify a plain reply and a real file read after a Cline upgrade. |
| `Install-ClinePeerGuard.ps1` | Installs `~/.cline/plugins/peer-guard.js`, a deny list (not a sandbox) active only when `AGENTHUB_PEER_GUARD=1` and `CLINE_SESSION_BACKEND_MODE=local`; it fails open in hub mode. Blocks git push, reset --hard, clean -f, mutating gh, publish, cloud CLIs, scheduled tasks and services, host administration, credential dumps, disk and power operations, recursive root/home deletes, and writes to protected paths. |
