# Host details

Read when: dispatching to Cline, OpenCode, Factory, Devin, Gemini, Warp or Copilot, resuming a Cline session, or auditing a host plugin.

Contents: Account hosts, Factory, Devin, Warp, Cline, OpenCode, Plugin installers.

## Account hosts

- Cursor Agent, Amp, Qoder, OpenCode: account login; confirm with the host's own status command before the first dispatch.
- Gemini: the dispatcher passes `--approval-mode yolo`; the registered shim skips its own yolo default for that invocation and adds `--skip-trust`. Complete Google OAuth interactively with `gemini` before use. Temporary task files are admitted with `--include-directories`.
- Copilot: runs on the `sh-pendoah` GitHub account; the dispatcher reads that token from gh's keyring into the child environment only.
- Codex reads the task from stdin (`exec --skip-git-repo-check -`) and does not initialize Git. Antigravity gets `--print=<prompt>` after its permissions flag.
- Long, quoted or multiline argument prompts go through a temporary UTF-8 file and a short pointer; the file is removed on completion.
- The Claude host is disabled in `dispatchPolicy`. An explicit `-HostId claude -AnthropicApiKey` run is the only opt-in; it refuses once `apiKeyOptIn.expiresUtc` has passed and for every other host.

## Factory

Dispatch stays governed while the host is disabled. `exec --auto` runs at low or medium only (`high` permits git push; `--skip-permissions-unsafe` is never emitted). `-o json` returns a session id and credit usage. `-m` defaults to `dispatchPolicy.factory.model`; `-Model` refuses anything outside `dispatchPolicy.factory.allowedModels`. `--settings` points at `factory/runtime-settings.json`, checked with `droid rules check`.

## Devin

Local only: `devin -p --prompt-file`, never `--cloud`. `--model` defaults to `dispatchPolicy.devin.model`; `-Model` refuses anything outside `dispatchPolicy.devin.allowedModels`. Permission mode is `dangerous` by owner direction and Windows has no Devin sandbox, so run Devin only in `C:/wt` worktrees.

## Warp

The child sets `WARP_CLI_MODE=1` and never opens the terminal GUI. A recorded `dispatchPolicy.warp.mcpConfig` is passed as `--mcp` with `--mcp-startup-timeout 30s` after resolving its `{userHome}` template; a missing file skips both flags with one stderr warning, and the file is never read or printed. Keep Warp disabled unless an account-status command and a local-only mode are both verified.

## Cline

Cline dispatch is disabled by owner policy. When enabled:

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
