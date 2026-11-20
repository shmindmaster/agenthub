# Z.ai ZCode

Standalone ZCode is a retained fleet agent. On the verified Windows host, ZCode Desktop is the signed 3.18.2 release (file build 3.18.2.10443). Its bundled Agent CLI reports 0.17.1. AgentHub uses the invoking Windows user's `~/.zcode/cli` profile for this install. AutoClaw's account-specific ZCode runtime has a separate profile. [Install](https://zcode.z.ai/en/docs/install) · [ZCode source and distributions](https://github.com/zai-org/ZCode/blob/main/README.en.md)

## Configure and verify

From the AgentHub checkout, audit the native marketplace or deploy it with ZCode closed:

```powershell
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -HostId zcode -IncludePrivateOverlay -Json
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -HostId zcode -IncludePrivateOverlay -Apply
node scripts/agenthub-cli.mjs doctor --host zcode --native
```

Omit `-IncludePrivateOverlay` for public AgentHub and Parallel only. Use `-PluginId parallel` to limit the marketplace operation to Parallel. The dedicated command uses the native bundled CLI to register tracked AgentHub marketplace snapshots and the official Parallel GitHub marketplace. The seven public packages, three private packages and Parallel 0.12.0 were read back at their expected versions on Windows. The private on-demand LinkedIn plugin is installed and starts disabled. Use Settings → Plugins in ZCode to inspect active packages in the workspace. [ZCode plugins](https://zcode.z.ai/en/docs/plugin) · [Parallel Agent Skills](https://docs.parallel.ai/integrations/agent-skills)

The desktop and bundled CLI are the verified installation surfaces. ZCode Desktop is also the vendor's development environment, with an integrated terminal, previews and DevTools. The open-source unified distribution also provides TUI and local Web modes. Its launcher and Web mode require separate installation and acceptance. Remote Development runs tasks in a separate workspace over SSH, Docker or WSL. Remote Control and Bot Channel connect to an existing desktop session. Both routes need separate acceptance. [ZCode IDE](https://zcode.z.ai/en/docs/ADE-tools) · [ZCode distribution](https://github.com/zai-org/ZCode/blob/main/README.en.md#zcode-cli-distribution)

AgentHub dispatch awaits a successful model request from a disposable workspace. The Windows desktop bundle needed explicit paths to its built-in and personal provider configuration for a headless prompt. With both paths set, the CLI started and returned "Select a model before sending a message." Marketplace and skill inventory run independently of model selection.

## MCP and accounts

Use Settings → MCP for native connector inventory and use the managed marketplace plugin where it supplies the service. For additional services ZCode supports HTTP and SSE, with OAuth for compatible remote servers. Use **Open authorization** on that service's row and approve with the intended provider account, then verify the resulting tool list and make a read-only call in a fresh workspace. Local stdio uses the runtime environment. Direct user MCP entries live under `mcp.servers` in `~/.zcode/cli/config.json`. Doctor reads that user file and lists declared plugin MCP names using the native CLI. Account approval and tool invocation are separate checks. [ZCode MCP](https://zcode.z.ai/en/docs/mcp-services)

For model sign-in use the desktop **Connect** action for the intended Z.ai or BigModel account, or the vendor CLI's `login` command. Parallel's official marketplace package declares its Search MCP. For the funded personal account, Parallel's current authenticated route is `https://mcp.parallel.ai/mcp?login` with OAuth enabled in the native MCP form. Keep tokens in the host or provider credential store. [ZCode model connection](https://zcode.z.ai/en/docs/configuration) · [Parallel MCP](https://parallel.ai/mcp)

The Windows desktop protocol discovered the Parallel Search, AssemblyAI Docs and AssemblyAI service declarations. Separate unauthenticated endpoint checks initialized the Parallel Search and AssemblyAI Docs services and received OAuth challenges for the Parallel login endpoint and the AssemblyAI service. A bounded native connection check timed out. The anonymous Parallel endpoint returned seven tools and its web_fetch call retrieved the expected public test page. Separate unauthenticated checks initialized Clerk, Exa and AWS; Descript, Linear, Notion and Devin returned authorization challenges. Funded Parallel consent and tool calls from a ZCode session still require acceptance.

## Browser

ZCode's official Browser Use plugin was verified enabled at 0.5.1. Under **Settings → Browser** enable built-in browser control and start a fresh task. Use the right-hand desktop browser panel to watch the agent work. You can open your own tabs in that panel. For initial verification use a local fixture with a form, a known-value table, and a console message. Confirm which tab the agent controls, test manual work in a separate tab, and verify the screenshot and DevTools output. [ZCode browser automation](https://zcode.z.ai/en/docs/browser-use)

AH Browser is installed through the AgentHub marketplace. The copy installed in ZCode passed a loopback fixture from a shell. It submitted a form, extracted a known table row, captured console and network evidence, and produced a screenshot and a decodable video. For Media Studio capture and visible, cooperative work, use a dedicated session and the acceptance checks in the [fleet browser runbook](browser-fleet.md). The BrowserSkill bridge and native desktop browser interactions have separate acceptance. [BrowserSkill manual](https://browserskill.weixin.qq.com/manual.en.html)
