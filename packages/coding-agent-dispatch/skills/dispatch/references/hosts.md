# Host details

Read when: dispatching to Cline, OpenCode, Factory, Devin, Warp or Copilot, reviewing Kilo or MiMo eligibility, resuming a Cline session, or auditing a host plugin.

Contents: Account hosts, Factory, Devin, Warp, Cline, OpenCode, Plugin installers.

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
its own multiplier; only an allowlisted model may be routed. The Kiro IDE and
KiroCrew are not dispatch targets.

Qwen has a saved configuration, but its observed run failed in
`resolveModelConfig`. Do not describe it as callable or change its credentials
to make a check pass.

## Factory

Dispatch is governed. `exec --auto` runs at low or medium only (`high` permits git push; `--skip-permissions-unsafe` is never emitted). `-o json` returns a session id and credit usage. `-m` defaults to `dispatchPolicy.factory.model`; `-Model` refuses anything outside `dispatchPolicy.factory.allowedModels`. `--settings` points at `factory/runtime-settings.json`, checked with `droid rules check`.

## Devin

Local only: `devin -p --prompt-file`, never `--cloud`. `--model` defaults to `dispatchPolicy.devin.model`; `-Model` refuses anything outside `dispatchPolicy.devin.allowedModels`. Permission mode is `dangerous` by owner direction and Windows has no Devin sandbox, so run Devin only in `C:/wt` worktrees.

## Warp

The child sets `WARP_CLI_MODE=1` and never opens the terminal GUI. A recorded `dispatchPolicy.warp.mcpConfig` is passed as `--mcp` with `--mcp-startup-timeout 30s` after resolving its `{userHome}` template; a missing file skips both flags with one stderr warning, and the file is never read or printed. Keep Warp enabled only while an account-status command and a local-only mode are both verified.

## Cline

Cline dispatch is enabled in `dispatchPolicy`:

- Uses the saved provider settings in the private Cline profile (keys stay there), `--json` execution, low thinking and the dispatcher timeout. Native skills, plugins and MCP are retained. Do not use `--yolo`.
- Resume: `-HostId cline -SessionId <id>` uses ACP `session/load` (the `--id` flag forces interactive mode). It starts a windowless ACP child after the normal gates, keeps task text on stdin, cancels permission requests (tasks needing permission can stop early), stops its child tree on completion, and returns JSON with `sessionId`, `text` and `stopReason`. Other hosts refuse `-SessionId`. A live resumed prompt is unverified.
- `cline --acp` is an on-demand stdio ACP agent. The ACP client owns permission handling; keep `--auto-approve false` unless the task authorizes otherwise. Do not install an A2A/AMCP bridge or invent a Codex ACP setting.
- `cline/acp-session.mjs` is a transport-only client for caller-owned streams.

## OpenCode

`opencode acp` is the native stdio ACP server, sharing the persisted account and configuration. The ACP client owns permission handling.

## Plugin installers

Each installer audits by default and changes files only with `-Apply`. None starts a host, registers background maintenance, or changes credentials. Re-audit after a host update.

| Script | Purpose |
| --- | --- |
| `Install-OpenCodeToolDiscovery.ps1` | Native global plugin that defers schemas and skill/MCP catalogs until needed. Reload the shared OpenCode service after installing. |
| `Install-ClineToolDiscovery.ps1` | Installs `cline/lightweight-chat.js` (`find_tools` loads up to five tools per search) for the `qwen3.8-max` profile, and sets Cline's global `compactionEnabled` to `false`, because compaction otherwise estimates the full tool catalog and can discard tool results. Verify a plain reply and a real file read after a Cline upgrade. |
| `Install-ClinePeerGuard.ps1` | Installs `~/.cline/plugins/peer-guard.js`, a deny list (not a sandbox) active only when `AGENTHUB_PEER_GUARD=1` and `CLINE_SESSION_BACKEND_MODE=local`; it fails open in hub mode. Blocks git push, reset --hard, clean -f, mutating gh, publish, cloud CLIs, scheduled tasks and services, host administration, credential dumps, disk and power operations, recursive root/home deletes, and writes to protected paths. |
