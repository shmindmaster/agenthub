# AH-Browser plugin

Automate a website in an existing Chrome or Edge profile, or use an isolated browser for clean-state testing and capture. The skill selects a native browser, Tencent BrowserSkill, or the bundled agent-browser wrapper according to the task and the host. See [browser routing](skills/automate/references/hosts.md).

## Contents

| Path | Purpose |
|---|---|
| `skills/automate/SKILL.md` | The only skill: choose the browser, the command loop, the rules |
| `skills/automate/scripts/browse.mjs` | Wrapper around agent-browser: per-directory session, no visible window, output cap, captured output, idle exit |
| `skills/automate/references/testing.md` | Procedure and report format for testing an app as a user |
| `skills/automate/references/hosts.md` | Native browser per host, engines, signed-in sites |
| `tests/browse.test.mjs` | Offline tests, including the daemon-holds-the-pipe hang |

## Engines

For existing Chrome and Edge profiles, install the [BrowserSkill CLI and extension](https://github.com/Tencent/BrowserSkill/blob/cli-v0.4.2/AGENT_INSTALL.md). Enable the extension in each intended profile. Run `bsk doctor`, then verify each chosen connection using a public page and close the test session.

For isolated sessions, install agent-browser with `npm i -g agent-browser && agent-browser install`. The wrapper starts the engine on demand and provides accessibility snapshots with element refs. Playwright CLI is the fallback. The plugin ships guidance and the wrapper. Each engine is installed separately.

## Test

```bash
node --test tests/browse.test.mjs
```
