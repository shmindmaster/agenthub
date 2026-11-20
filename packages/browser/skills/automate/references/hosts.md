# Which host has a browser

For general browsing, use the host's own tool when the row says native. Otherwise use `scripts/browse.mjs`. Use the signed-in profile workflow below when the task needs an existing session. Hosts change, so verify what the session can actually call.

| Host | Native browser | Use |
|---|---|---|
| Claude Code, Claude Desktop, Cowork | Plan browser while that tool answers. A third-party gateway session has none. | Native when it answers; otherwise the client |
| Codex app | `@Browser`, `@Chrome`, Computer Use | Native; the Codex CLI is unreliable, use the client |
| Cursor IDE | `@browser` | Native; Cursor Agent CLI has none, use the client |
| VS Code (Copilot chat) | Integrated browser tools | Native |
| Antigravity | Browser Subagent | Native |
| Factory Droid | droid-control, which runs agent-browser | Native |
| Grok CLI | none | Use the client |
| Copilot CLI | screen-level computer use only | Use the client |
| Amp | none | Use the client |
| Cline CLI | official `agent-browser` plugin | Native |
| Devin CLI | none confirmed | Use the client |
| OpenCode with Browse | `tools.browse.*` when installed and callable | Native Browse; verify live relay and extension status |
| Warp | cloud sandbox only | Use the client |

Computer Use and any headed browser take the foreground and show a window. Avoid them for background work.

## OpenCode Browse

Prefer the callable native Browse tools for an existing Chrome profile. Read
`browse.status` (or `browse status --json` from the native Browse CLI) before
diagnosing a connection. A running relay alone does not prove the extension is
connected. Recheck an old `paired-offline` result; an already connected extension
needs no restart or re-pairing. Check the intended profile and extension only when
the fresh status still reports them offline. Do not open or foreground the user's
browser to run a diagnostic. Keep agent tabs in the background; use
`browse.handoff` only for a real human login, consent, CAPTCHA or payment step.
The installed tool list varies by version; inspect this session's tools instead
of assuming a fixed count. Use the client fallback only if native Browse cannot
perform the required operation. A cloud browser has its own sessions and does not
inherit desktop logins.

Before asking for a repository list or starting cloud setup, reuse the current
request, connected tracker and prior environment records. Verify existing
environments and their exact revision before proposing replacements. An old
offline browser result does not imply that cloud environments are missing.

## Engines

- **agent-browser** is the default. `node scripts/browse.mjs doctor` reports whether it and Chrome are present. Install once with `npm i -g agent-browser && agent-browser install` (roughly 120 MB plus a Chrome download).
- **playwright-cli** is the second engine for a host that cannot run agent-browser, and for Firefox or WebKit. Run `playwright-cli --help`. Its security boundary is weaker; keep it on trusted sites.
- A host with no shell needs a callable native browser or an approved runner. The fleet's Playwright MCP and Chrome DevTools MCP registrations are retired.

## Existing Chrome and Edge profiles

Use Tencent BrowserSkill locally when the native tool cannot reach the selected profile. Follow the [official setup guide](https://github.com/Tencent/BrowserSkill/blob/main/AGENT_INSTALL.md) for the CLI and user-controlled extension setup. AH Browser supplies the routing skill. Keep the daemon local and start it on demand. A remote or sandboxed agent needs a separately authorized bridge to use a desktop profile. Read [BrowserSkill workflows](browserskill.md) for video, structured output and diagnostics.

1. Run `bsk browsers --json`. Match the requested profile by its exact label or instance ID. Match the browser name only if the user selected that browser and it has one eligible connection. With multiple eligible connections or an unnamed profile that cannot be identified, resolve the ambiguity with the user. If the daemon is offline, start it with `bsk daemon start --mode local --quiet` and recheck. If the daemon responds but no browser connects, run `bsk doctor` and check that the intended profile is open with the extension enabled.
2. If a Windows host cannot launch the daemon independently because of its Job Object, run `bsk daemon start --mode local --foreground` in a persistent host task. Probe with `bsk status` from a separate call. Set `BSK_AUTO_START=0` for each client call when using that task. Use the same OS user and `BSK_HOME`. Reuse a healthy daemon. The vendor daemon can exit when idle, so check readiness before each new task.
3. Run `bsk session start --browser <instance-id> --no-focus --json`. Keep the returned `session_id` and confirm `browser_instance_id` equals the selected ID before navigating. The Agent Window uses the profile's existing sign-in. Borrow an existing tab only when the user authorizes that tab and the browser confirms it.
4. Run `bsk navigate <url> --session <id>`, then `bsk cooperate sync --session <id> --json`. Scope every page command to that session and pass the fresh single-use `context_id` as `--context` on a subsequent shared-tab action. Re-sync after human input or a rejected context and reconsider the action against the current page. Verify any uncertain outcome before retrying. Keep cookies, tokens, pairing links and credential fields out of outputs.
5. Run `bsk session stop <id>` even if the task fails. Stop only the session you started. Report an unavailable profile and preserve the chosen account boundary.

For isolated sign-in, use the client's encrypted `auth` vault. On explicit request, the client can copy a Chrome profile with `--profile <name>` while Chrome is closed, or attach with `--auto-connect` when remote debugging is enabled.
