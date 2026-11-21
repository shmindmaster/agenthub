# Browser setup and acceptance

AgentHub configures vendor tools and supplies AH Browser for common workflows. Prefer the vendor's native browser where it meets the task's requirements. For visible work that needs a real profile and cooperative control, use an authorized native tab or Tencent BrowserSkill's background Agent Window. For repeatable tests and Media Studio pointer receipts, use an isolated AH Browser recording session.

## Visible and cooperative work

1. Select a browser surface, named browser instance or user-owned profile and a task identity. Use a distinct tab or background window for each writer. Site data from a signed-in profile stays in that profile unless the task authorizes exporting it.
2. Use the provider's tab group if available. BrowserSkill runs a dedicated Agent Window with task tab indicators; it discontinued automatic native tab groups. In a tool that supports user-selected tab sharing, wait for that selection before taking control. Publish the window or group label so the user can choose to watch.
3. Let the user and other tools act in other tabs. When a person steps into the task tab, pause, verify the settled page and resume using fresh references. BrowserSkill uses a fresh cooperative context for shared-tab actions. Moving one of its controlled tabs out of the Agent Window ends that session and preserves the tabs.
4. Scope every action to the task's tab and instance. Stop only your session. Leave credential prompts, CAPTCHAs and confirmation steps to the user when required by the site or permission boundary. See [BrowserSkill setup](../../packages/browser/skills/automate/references/hosts.md) and [workflows](../../packages/browser/skills/automate/references/browserskill.md).

## Native control by interface

These are setup routes and vendor claims. A working receipt requires a fresh session on the actual installed interface and account.

| Interface | Vendor setup and practical boundary |
| --- | --- |
| ChatGPT/Codex desktop and cloud | Use the built-in browser for an isolated page and Settings → Browser → Agent permissions. Use the official ChatGPT extension and explicitly select a tab for a signed-in Chromium profile. Cloud uses its own sandbox browser if available. Verify CLI and IDE routes separately. [Browser docs](https://learn.chatgpt.com/docs/browser) · [Extension](https://learn.chatgpt.com/docs/chrome-extension) |
| Claude Code, Desktop, Cowork | Use the vendor Claude in Chrome extension with the intended Claude account, then enable the Chrome integration in the local Claude Code session. In Desktop/Cowork, check the actual browser tool and permissions in the signed-in workspace. Hosted and gateway sessions need their own route. [Claude Code with Chrome](https://code.claude.com/docs/en/chrome) |
| Cursor IDE and Agent CLI | Use Cursor's native Browser tool in the IDE, check tool mode and site allowlist, then verify screenshots and action results. Verify the CLI and hosted agent separately before claiming the GUI route. [Cursor browser](https://prod.cursor.com/docs/agent/tools/browser) |
| VS Code Insiders and Copilot | Keep integrated tools under `workbench.browser.enableChatTools`. For manual co-control select Share with Agent and revoke via the same control. For local Chrome/Edge preview use the official Copilot browser extension, Node 22+, `chat.agentHost.browserUse.enabled`, restart and enable `browser-use` in Copilot chat. Standalone Copilot CLI and cloud need separate receipts. [VS Code browser tools](https://code.visualstudio.com/docs/agents/run/browser-tools) |
| Google Antigravity | Configure Settings → Browser where available and probe `/browser` in the app, `agy`, IDE or official extension. The CLI, desktop and enterprise rollout have different browser options and admin permissions. A host-bundled implementation does not require an AgentHub Chrome DevTools MCP registration. [Browser](https://antigravity.google/docs/browser) · [Command](https://antigravity.google/docs/commands/browser) |
| OpenCode | The official Browse extension and relay support named sessions, Chromium background groups, handoff, recording and HAR. Use vendor distribution and confirm the selected extension/relay via the live status before claiming pairing. Local and hosted clients have different browser state. [Browse](https://opencode.ai/product/browse) |
| Kilo | Enable browser automation in the VS Code extension's Settings → Web Tools and inspect the CLI's own browser settings. Desktop's in-app browser can open a preview without giving the agent DOM access. Use AH Browser for capture or automation when native tools cannot do it. [Browser Use](https://kilo.ai/docs/code-with-ai/features/browser-use) · [Desktop preview](https://kilo.ai/docs/desktop/features/browser) |
| Factory | Install Droid Control from Factory's official plugin marketplace and use its documented runtime prerequisites when needed. It uses agent-browser for browser automation and can record evidence. Check GUI and cloud separately. [Droid Control](https://docs.factory.com/automations/droid-control) |
| Cline | Inspect whether the current CLI/plugin marketplace exposes the documented browser tools before use. In the IDE, Desktop, Kanban and hosted Cloud Agents, confirm actual support and scope independently. Use AH Browser in shell-capable local routes where the native tool is unavailable. [Cline surfaces](https://docs.cline.bot/cline-overview) · [Cloud Agents](https://docs.cline.bot/usage/cloud-agents) |
| Devin | Install and inspect local plugins with the Devin CLI. In Desktop, check the same plugin under Devin Local customizations. Verify ACP and Cloud independently and confirm the cloud VM can reach the intended test app. Use AH Browser for shell-capable local sessions. [Devin plugins](https://docs.devin.ai/product-guides/plugins) |
| Grok Build | Use AH Browser on the local CLI or shell-capable ACP client when browser control is needed. [Grok Build](https://docs.x.ai/build/overview) |
| Grok Bot | In app settings connect only the intended account and configure a remote custom connector under Apps. Live browser state belongs to the Bot computer and can be shared across bots on the same account. Verify each bot and connector scope separately. [Grok Bot computer and apps](https://docs.x.ai/grok-bot/computer-and-apps) |
| Manus Desktop and Web | Add a remote connector through Connectors → Create → Add MCP by URL. Verify the Desktop and Web clients separately. Select an authorized Browser Operator profile for tasks that need signed-in browser state. [Manus connectors](https://www.manus.im/features/connectors) |
| Amp | Use AH Browser locally when no callable browser is exposed. Desktop/mobile clients and Orbs have their own contexts and need evidence separately. [Amp docs](https://ampcode.com/docs) |
| Kiro and KiroCrew | Use the IDE or CLI's approved tool route or a shell-capable AH Browser session. Treat Web and Crew as separate surfaces. Browser delivery for local profile interaction is unverified. [Kiro surfaces](https://kiro.dev/docs/) |
| Z.ai AutoClaw | The bundled desktop runtime discovers AH Browser. Establish native browser scope and control with a disposable fixture before using personal profiles. Verify the desktop browser session separately. [AutoClaw setup and acceptance](autoclaw.md) |
| Z.ai ZCode | The standalone desktop installs the official Browser Use plugin alongside AH Browser. Use the right-hand Browser panel for visible work and a dedicated AgentHub browser session for recording or structured extraction. [ZCode setup and acceptance](zcode.md) |
| Warp/Oz, Qwen Code, MiMo, Gemini CLI, Windsurf/Cascade and CodeRabbit | Inactive or specialist lanes. Do not turn prior retirement into an install target. A future reactivated CLI can use its documented vendor interface or an approved shell route. |

## Browser engines

BrowserSkill documents Chrome and Edge. Use a named instance and an authorized extension from the vendor manual. The ChatGPT extension and OpenCode Browse document a wider set of Chromium browsers. Confirm the official extension supports the specific browser before attempting to connect it. Firefox and WebKit use the isolated Playwright CLI where installed for compatibility testing; desktop Safari is a separate browser and needs its own verification. [BrowserSkill](https://browserskill.weixin.qq.com/manual.en.html) · [OpenCode Browse](https://opencode.ai/product/browse) · [Playwright browsers](https://playwright.dev/docs/browsers)

### Isolated Edge with a domain allowlist

On Windows with Edge 157 and agent-browser 0.43.0, putting the URL in the first command of a fresh allowlisted session can report a successful navigation and leave the next command at `about:blank`. Start the session with a URL-less `open`, then navigate separately. Keep the same session and allowlist on each command. Verify the active URL before interacting with the page.

```powershell
$wrapper = 'packages/browser/skills/automate/scripts/browse.mjs'
$edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
$session = "ah-edge-$([guid]::NewGuid().ToString('N'))"
$browserArgs = @('--session', $session, '--allowed-domains', '127.0.0.1')
$fixtureUrl = 'http://127.0.0.1:8080/'

try {
    node $wrapper @browserArgs --executable-path $edge open
    if ($LASTEXITCODE -ne 0) { throw 'Edge did not start.' }
    node $wrapper @browserArgs open $fixtureUrl
    if ($LASTEXITCODE -ne 0) { throw 'Edge navigation failed.' }
    $activeUrl = node $wrapper @browserArgs get url
    if ($LASTEXITCODE -ne 0 -or $activeUrl -ne $fixtureUrl) {
        throw 'Edge did not retain the requested page.'
    }
    node $wrapper @browserArgs snapshot -i
} finally {
    node $wrapper @browserArgs close
}
```

Set `$fixtureUrl` to the running loopback fixture. The tested sequence retained the page across form submission, table extraction, console and network inspection, and video capture. A navigation to the non-allowlisted `localhost` hostname was denied and the allowed page remained active.

## Remote MCP and OAuth

- Use the vendor's native marketplace/plugin if it supplies the requested integration with the right transport and permissions. Register the official remote endpoint through a supported native configuration when the vendor documents that path. Keep one integration owner per host. Use local browser helpers only on demand where the browser and profile live. Remote tools do not inherit a local browser profile.
- For OAuth, verify the server supports the exact client's login method, expected issuer, and minimal scopes. Use the provider's consent flow under the intended identity. Host login, browser login and MCP OAuth are separate. Keep tokens in native storage or runtime secret references. Preserve existing revocation and write approval controls.
- For Tavily in Cline, keep the vendor's hosted Streamable HTTP endpoint and Cline-managed OAuth state. A bare HTTP 401 does not establish that the Cline connection needs new consent. The official Cline SDK's passive `probeMcpServerConnection` can refresh a saved authorization without opening a browser. If it still reports authorization required, use `cline mcp` → **Authorize OAuth** and select the intended Tavily account. Check the tool list after connecting. [Cline MCP configuration](https://github.com/cline/cline/blob/main/docs/mcp/mcp-overview.mdx) · [Tavily OAuth](https://github.com/tavily-ai/tavily-mcp#remote-mcp-server-oauth-flow)
### Parallel and Tavily

Use the same provider endpoints and tool capabilities across the fleet. Keep existing native names and account grants. Check a fresh session for a duplicate provider tool list when a marketplace also loads an MCP server.

| Provider | Remote endpoint | Access |
| --- | --- | --- |
| Parallel search and fetch | `https://mcp.parallel.ai/mcp` | Free, rate-limited anonymous access. Append `?tools=web_search,web_fetch` to expose only those two tools. |
| Parallel research | `https://mcp.parallel.ai/mcp?login&tools=web_research` | Native OAuth under the intended Parallel account. A separate research-only connection keeps duplicate search tools out of context. Before using it, verify the account and usage attribution. |
| Tavily | `https://mcp.tavily.com/mcp/` | Native OAuth for search, extract, crawl, map and research. Use the intended account and keep consent with the host. |

[Parallel MCP and billing](https://docs.parallel.ai/integrations/mcp/quickstart) · [Parallel Agent Skills](https://github.com/parallel-web/parallel-agent-skills) · [Tavily MCP](https://docs.tavily.com/documentation/mcp)

| Interface | Native setup and readback |
| --- | --- |
| Claude Code | Use the official Parallel marketplace. Add Tavily with `claude mcp add --scope user --transport http tavily https://mcp.tavily.com/mcp/`. Use `/mcp` to authorize and inspect tools. [Claude setup](https://docs.tavily.com/documentation/mcp#connect-to-claude-code) |
| Codex | Keep the vendor Parallel skills and existing native anonymous connection. Tavily supports `codex mcp add tavily --url https://mcp.tavily.com/mcp/` and `codex mcp login tavily`. Use one effective Tavily connection when the ChatGPT/Codex plugin is also installed. [Codex setup](https://docs.tavily.com/documentation/mcp) |
| Factory Droid | Keep `parallel-search` in `~/.factory/mcp.json`. Use `droid mcp add tavily https://mcp.tavily.com/mcp/ --type http` when missing. Use `/mcp` for Tavily consent and on-demand Vision. `droid mcp list` reports connections. [Factory MCP](https://docs.factory.com/harness/mcp) |
| Cursor and VS Code Insiders | Use the native user MCP config. Cursor uses `url` in `~/.cursor/mcp.json`. VS Code uses `type: "http"` and `url` in the `servers` map. Authorize independently in each editor. [Tavily editor setup](https://docs.tavily.com/documentation/mcp) |
| Cline CLI and extension | Use separate native Streamable HTTP registrations and native OAuth. When a saved authorization exists, probe it first. A new extension registration can be enabled and authorized in its MCP panel. [Cline MCP](https://github.com/cline/cline/blob/main/docs/mcp/mcp-overview.mdx) |
| OpenCode and Kilo | Use native remote entries and `opencode mcp auth tavily` or `kilo mcp auth tavily`. OpenCode 2 uses `mcp.servers` for native entries. Its separate vendor npm plugin needs its own authorization. [OpenCode MCP](https://opencode.ai/docs/mcp-servers/) · [Kilo CLI MCP](https://docs.kilo.ai/automate/mcp/using-in-cli) |
| Amp | Use `amp mcp add tavily https://mcp.tavily.com/mcp/` and let the TUI handle OAuth. Amp CLI uses its local secret store. [Amp MCP](https://ampcode.com/docs/customize/mcp) |
| Grok Build | Keep native hosted entries in `~/.grok/config.toml`. Check for imported duplicates with `grok inspect`. Use `/mcps` to authenticate OAuth servers. [Grok Build MCP](https://docs.x.ai/build/features/mcp-servers) |
| Devin CLI | Keep the vendor Parallel plugin. Use `devin mcp add --scope user tavily https://mcp.tavily.com/mcp/` and `devin mcp login tavily`. Cloud and desktop scopes need separate readback. [Devin CLI MCP](https://docs.devin.ai/cli/extensibility/mcp/configuration.md) |
| Copilot CLI | Keep the vendor Parallel plugin. Use `copilot mcp add --transport http tavily https://mcp.tavily.com/mcp/`. Confirm OAuth in the installed CLI or use a supported account connector. Copilot cloud agent and code review do not support custom OAuth MCP servers. [CLI setup](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers) · [Cloud limitations](https://docs.github.com/en/copilot/concepts/customizations/mcp) |
| Antigravity CLI and IDE | Use the vendor Parallel plugin where available. Register Tavily with `serverUrl` in the applicable native `mcp_config.json`. Authorize in Customizations and verify each surface. [Antigravity MCP](https://antigravity.google/docs/ide-mcp) |
| ZCode and AutoClaw | Keep the vendor Parallel plugin in the relevant profile. Add Tavily as HTTP with OAuth enabled in the native MCP settings. AutoClaw uses an account-specific runtime. Check the effective registration and consent in the intended app and profile. [ZCode MCP](https://zcode.z.ai/en/docs/mcp-services) · [AutoClaw runbook](autoclaw.md) |
| Hosted agents | Use the service's own connector UI. Manus documents custom remote MCP setup. Confirm each account and workspace. A CLI registration is independent of the hosted account. [Manus Connectors](https://manus.im/docs/integrations/mcp-connectors) |

## Acceptance per interface

1. Record the host version, browser version, browser instance, mode, extension source and callable tools in a fresh session.
2. Open a synthetic page. Prove a form change and resulting state, structured table or list output, an expected console event and network response, and an authorized screenshot or video. Verify output and file playback. For Media Studio targeted footage, keep the timed pointer receipt and the recording together.
3. For visible sessions, have the user interact in another tab and voluntarily take the task tab once. Prove that the agent yields and resumes from freshly observed state. Confirm a second tool remains confined to its own tab. Stop the task and read back that borrowed tabs were returned or preserved.
4. For each requested connector, separately record installation, tools discovered, one safe call and a permission denial where applicable. A listing alone does not establish usable OAuth access.

## Fleet health checks

Run `node scripts/agenthub-cli.mjs doctor --all --probe-remote` to audit installed configurations and validate anonymous MCP handshakes. A successful handshake and an authentication challenge are distinct results. Use host-native MCP listing for plugin-provided or signed-in servers and verify permitted calls before recording tool-level acceptance. Use `scripts/Sync-Plugins.ps1` in audit mode to compare AgentHub and private package versions with installed plugin versions.

Doctor reports a missing direct registration for a plugin-only host only if the server is allowed by that host's direct MCP policy and otherwise belongs in its default sync scope. Native plugin and account-level connector discovery still require host readback.

For Cline, Doctor reads both the flat MCP settings and the CLI's nested transport format. It preserves the server's enabled state and redacts credential values in its report.
