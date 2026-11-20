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
| Z.ai AutoClaw | Vendor documents browser automation and app MCP connections. Use a disposable authorized fixture to establish app browser profile scope and automation controls before connecting personal profiles. No CLI/IDE adapter is assumed. [AutoClaw](https://autoclaw.z.ai/about/) · [MCP](https://autoclaw.z.ai/docs/advanced/mcp-connectors/) |
| Warp/Oz, Qwen Code, MiMo, Gemini CLI, Windsurf/Cascade and CodeRabbit | Inactive or specialist lanes. Do not turn prior retirement into an install target. A future reactivated CLI can use its documented vendor interface or an approved shell route. |

## Browser engines

BrowserSkill documents Chrome and Edge. Use a named instance and an authorized extension from the vendor manual. The ChatGPT extension and OpenCode Browse document a wider set of Chromium browsers. Confirm the official extension supports the specific browser before attempting to connect it. Firefox and WebKit use the isolated Playwright CLI where installed for compatibility testing; desktop Safari is a separate browser and needs its own verification. [BrowserSkill](https://browserskill.weixin.qq.com/manual.en.html) · [OpenCode Browse](https://opencode.ai/product/browse) · [Playwright browsers](https://playwright.dev/docs/browsers)

## Remote MCP and OAuth

- Use the vendor's native marketplace/plugin if it supplies the requested integration with the right transport and permissions. Register the official remote endpoint through a supported native configuration when the vendor documents that path. Keep one integration owner per host. Use local browser helpers only on demand where the browser and profile live. Remote tools do not inherit a local browser profile.
- For OAuth, verify the server supports the exact client's login method, expected issuer, and minimal scopes. Use the provider's consent flow under the intended identity. Host login, browser login and MCP OAuth are separate. Keep tokens in native storage or runtime secret references. Preserve existing revocation and write approval controls.
### Parallel

- Use Parallel's native package in Claude Code, Codex, Devin, Factory, Copilot CLI and Antigravity. Claude Code and Devin load the unified hosted MCP. Codex and Antigravity use the vendor Search MCP. OpenCode uses the official npm plugin and needs Parallel authorization to execute its tools.
- Cursor offers a marketplace plugin with CLI-backed commands. Use the official skill installer and anonymous remote MCP while marketplace access is unavailable. In VS Code Insiders, use a native user-level remote MCP entry for anonymous search and fetch. Both entries use `https://mcp.parallel.ai/mcp?tools=web_search,web_fetch`.
- Install the vendor skills with the documented agent IDs for Cline, Amp, Kilo, Grok Build, Kiro CLI and the supported Google interfaces. The skill installer records its managed files in `~/.agents/.skill-lock.json`. Verify discovery using a fresh session in each interface.
- Keep anonymous search and fetching as the default. Parallel sign-in and API-key traffic can incur charges. Deep research, scheduled monitoring and CLI-backed calls may need sign-in. Use the intended account with explicit spend authorization. [Parallel MCP](https://parallel.ai/mcp) · [Agent Skills](https://docs.parallel.ai/integrations/agent-skills) · [Cursor plugin](https://docs.parallel.ai/integrations/cursor-marketplace) · [OpenCode plugin](https://docs.parallel.ai/integrations/opencode-plugin)

## Acceptance per interface

1. Record the host version, browser version, browser instance, mode, extension source and callable tools in a fresh session.
2. Open a synthetic page. Prove a form change and resulting state, structured table or list output, an expected console event and network response, and an authorized screenshot or video. Verify output and file playback. For Media Studio targeted footage, keep the timed pointer receipt and the recording together.
3. For visible sessions, have the user interact in another tab and voluntarily take the task tab once. Prove that the agent yields and resumes from freshly observed state. Confirm a second tool remains confined to its own tab. Stop the task and read back that borrowed tabs were returned or preserved.
4. For each requested connector, separately record installation, tools discovered, one safe call and a permission denial where applicable. A listing alone does not establish usable OAuth access.

## Fleet health checks

Run `node scripts/agenthub-cli.mjs doctor --all --probe-remote` to audit installed configurations and validate anonymous MCP handshakes. A successful handshake and an authentication challenge are distinct results. Use host-native MCP listing for plugin-provided or signed-in servers and verify permitted calls before recording tool-level acceptance. Use `scripts/Sync-Plugins.ps1` in audit mode to compare AgentHub and private package versions with installed plugin versions.
