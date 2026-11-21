# AutoClaw setup and acceptance

The Windows AutoClaw 2.5.3 app includes a ZCode 0.17.1 runtime. The desktop uses an account-specific runtime home and a newline-delimited desktop app-server protocol. Legacy `~/.openclaw-autoclaw` settings belong to a separate configuration path. Use Z.ai's documented desktop import and connector settings when managing a session from the app. [AutoClaw skills](https://autoclaw.z.ai/en/docs/advanced/skill/) · [MCP and connectors](https://autoclaw.z.ai/en/docs/advanced/mcp-connectors/) · [ZCode plugins](https://zcode.z.ai/en/docs/plugin)

## Native package setup

1. Select the intended AutoClaw account before writing. On the observed Windows build, the desktop launches the bundled runtime from `resources/vendor/zcode/zcode.cjs` with the account's `runtime/zcode-runtime/home` as its child process profile. Set the child process home explicitly. Confirm the effective plugin inventory before adding a marketplace.
2. Stage a clean, tracked public AgentHub checkout for the local marketplace. It uses the existing Claude-compatible manifest. Add that directory with the bundled runtime's `plugins marketplace add <directory> --scope user`. Install each catalog entry using `plugins install <name>@agenthub --scope user`.
3. Add Parallel's official marketplace using `plugins marketplace add parallel-web/parallel-agent-skills --scope user`. Install `parallel@parallel-agent-skills` with `plugins install parallel@parallel-agent-skills --scope user`. The marketplace uses the vendor package as published. [Parallel Agent Skills](https://docs.parallel.ai/integrations/agent-skills)
4. Read back installation and skills with `plugins list --json` and `skills list --json`. The desktop protocol's `plugins/list` and `mcp/list` confirm desktop-runtime discovery and connection state. Confirm the account and scopes before starting OAuth or permitting tool calls.

Run `agenthub doctor --host autoclaw --native --json` for repeatable inventory on Windows. Doctor uses the bundled runtime only when it finds exactly one initialized account profile. The JSON includes plugin IDs, versions, enablement, declared MCP names, and skill names. It excludes account paths, vendor diagnostics, and raw subprocess output. Desktop MCP connectivity and OAuth need their own live checks.

## Windows acceptance

The existing AutoClaw account reported all seven public AgentHub plugins enabled and all 15 Parallel skills discovered. The desktop runtime connected to Parallel and AssemblyAI Docs and reported eight and three tools respectively. The AssemblyAI service returned a failed connection in the credential-free check.

## Manage the native plugin catalog

```powershell
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -HostId autoclaw -Json
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -HostId autoclaw -AutoClawAccount <account-email> -Apply
```

Close AutoClaw before applying. The account must already be initialized on this Windows profile. The command compares the installed inventory with the public AgentHub catalog and the Parallel marketplace. Use `-PluginId` to select one plugin. Use `-IncludePrivateOverlay` with an explicit account only when that account is authorized for the private overlay. Apply requires validated, published AgentHub main and, if selected, the published private overlay main.

AgentHub stages tracked files under its local runtime directory and uses ZCode to register the catalogs and install or update plugins. It reports marketplace ownership conflicts without replacing the existing source. It preserves existing enablement choices and keeps capability-owned local MCPs with `startupEnabled: false` disabled. The built-in AutoClaw plugins remain under vendor control. General fleet sync and dispatch exclude AutoClaw.

Same-channel app update verification, desktop UI acceptance, and an authenticated tool invocation from an AutoClaw conversation remain open. To check the official update channel in the app, use Settings → About. [AutoClaw installation and updates](https://autoclaw.z.ai/en/docs/getting-started/install/)

AutoClaw mirrors its account-owned `autoglm-browser-agent` into the shared Windows skills directory. AgentHub recognizes the mirror when the skill document and signed service match the vendor account copy. The app reconciles that mirror on startup. Keep the account-owned skill intact and investigate any content mismatch before pruning.
