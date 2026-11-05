# AH-Browser plugin

Drive a hidden browser to automate a website task or test a web app as a user would. For hosts whose own browser is weak or missing (Grok, Copilot CLI, Amp, Cline, Devin and the other CLIs). Hosts with a high-fidelity native browser use that instead; `skills/automate/references/hosts.md` lists which.

## Contents

| Path | Purpose |
|---|---|
| `skills/automate/SKILL.md` | The only skill: choose the browser, the command loop, the rules |
| `skills/automate/scripts/browse.mjs` | Wrapper around agent-browser: per-directory session, no visible window, output cap, captured output, idle exit |
| `skills/automate/references/testing.md` | Procedure and report format for testing an app as a user |
| `skills/automate/references/hosts.md` | Native browser per host, engines, signed-in sites |
| `tests/browse.test.mjs` | Offline tests, including the daemon-holds-the-pipe hang |

## Engine

agent-browser (vercel-labs, Apache-2.0) is the default: a CLI with a Rust daemon that drives Chrome over CDP, needs no LLM key, and returns accessibility snapshots with element refs. Install once with `npm i -g agent-browser && agent-browser install`. The wrapper never installs anything. Playwright CLI is the documented second engine; this package ships no copy of either.

Why not a browser MCP server: a server costs a process and several times the context per task, and shell-only hosts cannot use one.

## Test

```bash
node --test tests/browse.test.mjs
```
