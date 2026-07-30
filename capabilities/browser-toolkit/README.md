# Browser Quality Toolkit

This capability gives every registered host, including Cursor IDE and Cursor
Agent, one shared browser-quality contract. Chrome DevTools MCP `@latest`
(currently 1.6.0) is the
live browser, diagnostics, Lighthouse, and trace layer. Existing Playwright
installations remain the deterministic regression layer when a repository
already owns them; this toolkit neither installs nor removes Playwright.

The canonical fleet deployment follows the upstream README's standard MCP
configuration: `npx -y chrome-devtools-mcp@latest`. Each host persists its own
native MCP entry, and the server starts Chrome only when a tool first requires
it. The server exposes its Chrome profile's pages, DOM, accessibility tree,
cookies, storage, request/response data, console output, and authenticated
application state to that agent. Use synthetic accounts and data, close
unrelated tabs, and sanitize screenshots, traces, logs, and reports.

Codex uses the upstream Windows 11 `cmd /c npx` form with its documented
environment and 20-second startup timeout. Antigravity uses the upstream
`127.0.0.1:9222` connection to its built-in browser. Every other supported
host uses the standard configuration rendered into its native schema.

## Concurrent agents

Chrome DevTools MCP is a local stdio server. Concurrent hosts can therefore
start one Node worker each; the upstream README does not define a shared server
transport. The server does not launch Chrome merely because an MCP client
connects, but it may keep its local worker alive for that host session.

The prior controlled QA routing remains available as an advanced, explicit
diagnostic mode:

```powershell
.\scripts\configure-agents.ps1 -Apply -BrowserMode Isolated
.\scripts\launch-agent-chrome.ps1 -Agent claude
.\scripts\launch-agent-chrome.ps1 -Agent qwen
.\scripts\launch-agent-chrome.ps1 -Agent opencode
.\scripts\launch-agent-chrome.ps1 -Agent hermes
```

This assigns ports 9341–9344 and separate browser profiles for those four
adapters. Use distinct
synthetic accounts, tenants, or seed namespaces too; browser isolation cannot
prevent two agents from mutating the same server-side record. Re-running the
fleet synchronizer restores the upstream README configuration.

## Responsibility boundary

| Layer | Owner | Use |
| --- | --- | --- |
| Live browser diagnostics | This toolkit / Chrome DevTools MCP | Existing-session reproduction, DOM and accessibility snapshots, console/network inspection, Lighthouse and performance traces |
| Quick Hermes browsing | Hermes native browser | Ordinary navigation and screenshots when deep DevTools evidence is unnecessary |
| Native desktop interaction | Qwen Code Computer Use | File pickers, native dialogs, and cross-application work that browser APIs cannot cover |
| Deterministic regression | Repository-owned Playwright, if present | Repeatable assertions, fixtures, cross-browser testing, trace/video evidence |
| Product audit/remediation | `product-experience-engineering` | Real-product discovery, UX/a11y audit, remediation, and readiness gates |
| Demo composition | `product-demo-studio` | Truth-checked capture, code-based composition, technical QA, and provenance |

Playwright MCP is not added by this capability. Existing installations are
preserved. No Windows-control MCP is installed. Chrome experimental screencast,
vision, memory, WebMCP, extension, third-party, and DevTools flags are not
enabled by AgentHub.

## Install and configure

Deploy the registry-selected native configuration and skills from AgentHub:

```powershell
cd C:\Repos\shmindmaster\agenthub
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Apply -Validate -IncludeInactiveAgents -ScopeProfile global-default
pwsh -NoProfile -File .\scripts\Apply-FullAccessAgentProfile.ps1
```

The package-local `configure-agents.ps1` remains only for the advanced
four-host QA routing described above. Applying it creates timestamped backups
under `%LOCALAPPDATA%\browser-toolkit\backups`, treats the existing
`QWEN_API_KEY` user variable as this toolkit's canonical secret name, and
merges only toolkit-owned settings. Qwen Code, OpenCode, and Hermes reference
that variable directly. It never prints a secret. Cursor's browser skills,
MCP registry, permissions, and launch policy are deployed by AgentHub's
full-profile reconciler instead of this package-local script.

If `QWEN_API_KEY` does not exist, set it without
putting it in shell history:

```powershell
$secret = Read-Host "Qwen Token Plan key" -AsSecureString
.\scripts\set-user-secret.ps1 -Name QWEN_API_KEY -Secret $secret
Remove-Variable secret
```

For Claude Code, the official Token Plan compatibility variable is
`ANTHROPIC_AUTH_TOKEN`. The configuration script copies from `QWEN_API_KEY`
only when the Claude variable is absent; it warns instead of overwriting when
the two existing values differ. QwenCloud's Qwen Code documentation calls its
example variable `BAILIAN_TOKEN_PLAN_API_KEY`, but Qwen Code's `envKey` is
configurable, so this toolkit consistently uses the user's canonical name.

## Run the controlled smoke test

```powershell
.\scripts\launch-qa-chrome.ps1
.\scripts\validate.ps1 -RunBrowserSmoke
```

The validation starts a local synthetic form, discovers MCP tools, takes an
accessibility snapshot, fills and submits the form, verifies the resulting
state, captures a screenshot, and records console/network/Lighthouse evidence
when the installed tool advertises those operations. Evidence is written under
the ignored `reports/browser-toolkit` directory.

The smoke fixture is not a substitute for validating an agent UI. Token-plan
response checks require a valid subscription and an interactive invocation of
each agent. Cursor was explicitly reauthorized on 2026-07-30. Its configuration
and plugin discovery may be verified without a paid model prompt; model-response
validation occurs only during authorized real work.

## Agent model endpoints

| Agent | API mode | Base URL | Default |
| --- | --- | --- | --- |
| Hermes | Anthropic messages | `https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic` | `qwen3.7-max` |
| Claude Code | Anthropic compatible | `https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic` | `qwen3.8-max-preview` |
| OpenCode | Anthropic SDK | `https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic/v1` | `qwen3.7-max` |
| Qwen Code | OpenAI compatible | `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1` | `qwen3.8-max-preview` |
| Cursor | OpenAI compatible, manual UI only | `https://coding-intl.dashscope.aliyuncs.com/v1` (Coding Plan) or `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1` (Token Plan Team) | Check plan docs; choose matching Cursor model name |

Current QwenCloud documentation says:
- Token Plan Team Edition uses `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`.
- Coding Plan uses `https://coding-intl.dashscope.aliyuncs.com/v1`.

Cursor provider credentials are still UI-managed and cannot be safely provisioned
from the project MCP adapter.

## Repository integration

- Vite: add `vite-plugin-devtools-json@1.1.0` only after proving workspace
  mapping improves the repository. Preserve plugin order and run native dev and
  production builds. Use a stable repository-specific UUID.
- Next.js: do not add the Vite plugin. Use Next.js source maps and native
  framework diagnostics.
- Monorepo: install this capability once; keep each application's native start,
  seed, reset, and artifact paths in that package.
- Existing Playwright: keep its version, config, fixtures, and package manager.
  Add the toolkit only for authenticated live-browser diagnosis.
- No seed/reset system: stop at an audit/readiness report. Add an idempotent,
  synthetic, environment-guarded seed/reset contract before deterministic
  capture.

See `adapters/*`, `skills/*`, and `templates/*` for complete host and workflow
contracts.

## Updates

1. Review official QwenCloud client pages and the Chrome DevTools MCP release.
2. Update exact versions in `package.json`, `versions.json`, MCP fragments, and
   adapter files together.
3. Run `npm install --package-lock-only`, `npm ci`, static checks, the browser
   smoke test, and one interactive smoke per enabled agent.
4. Review artifact redaction before committing.

## Rollback

Run:

```powershell
.\scripts\configure-agents.ps1 -RollbackFrom "<backup directory>"
```

This restores only files listed in that backup's manifest. Environment variables
must be restored manually from the recorded presence metadata; secrets are never
copied into backups. The dedicated QA profile can be deleted only after Chrome
is closed and after confirming the resolved path is under
`%LOCALAPPDATA%\browser-toolkit`.

## Authoritative sources

- QwenCloud client guides:
  [Hermes](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/hermes-agent),
  [Claude Code](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/claude-code),
  [Cursor](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/cursor),
  [OpenCode](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/opencode),
  [Qwen Code](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/qwen-code)
- [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- [Chrome DevTools for agents](https://developer.chrome.com/docs/devtools/agents)
- [Vite DevTools JSON plugin](https://github.com/ChromeDevTools/vite-plugin-devtools-json)

The executable product and demo gates come from the repository's canonical
`product-experience-engineering` and `product-demo-studio` capabilities.
