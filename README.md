# AgentHub

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)
[![CI](https://github.com/shmindmaster/agenthub/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/shmindmaster/agenthub/actions/workflows/ci.yml)

**Works in Claude Code but not in Codex? `npx agenthub doctor` shows every MCP server, skill and instruction file each of your coding agents actually loads, and what's broken, in about 10 seconds. Read-only. No account. No PowerShell.**

```bash
npx agenthub doctor
```

```text
AgentHub doctor 0.1.0 · read-only · no network
Home: /home/you   Registry: none, comparing agents with each other

AGENT             MCP  SKILLS  INSTRUCTIONS        ISSUES
Claude Code         3       2  CLAUDE.md ~684 tok  1 high · 2 warn
OpenAI Codex        2       2  AGENTS.md ~10 tok   2 warn
Gemini CLI          1       2  -                   1 warn
Cursor              2       2  -                   1 high
Cursor Agent CLI    2       2  -                   1 high

HIGH  MCP server 'postgres' has a GitHub token written into env.PG_TOKEN. Anything that reads, backs up or syncs this file can copy it.
      agents: claude · ~/.claude.json
      fix: Move it to an environment variable or the OS keychain and reference it, then rotate the exposed value.
HIGH  MCP server 'docs' talks to a remote host over plain http://, so requests and any credentials travel unencrypted.
      agents: cursor, cursor-agent · ~/.cursor/mcp.json
WARN  MCP server 'postgres' is configured differently across agents: claude -> stdio:node pg-mcp.js --readonly; codex -> stdio:node pg-mcp.js.
      agents: claude, codex
WARN  Two different copies of skill 'review-pr' are visible (~/.codex/skills and ~/.agents/skills); one shadows the other.
      agents: codex
INFO  MCP server 'filesystem' runs '@modelcontextprotocol/server-filesystem' through npx without a version, so every start can fetch and run a different release.
      agents: claude · ~/.claude.json

Summary: 5 of 21 agents found, 8 MCP server entries, 2 skills. 2 high, 3 warn, 8 info. Nothing was written.
```

That output is from a test fixture home, trimmed. Run it against your own machine to see yours.

## What doctor checks

- **Which agents are set up**, from their config files: Claude Code, Claude Desktop, OpenAI Codex, Cursor and the Cursor CLI, Gemini CLI, GitHub Copilot CLI, OpenCode, Cline, Amp, Devin, Factory Droid, Grok CLI, Google Antigravity, Warp, Windsurf, VS Code and VS Code Insiders. Paths come from [`registry/agents.json`](./registry/agents.json) and resolve per OS.
- **What each one loads**: its MCP servers (JSON, JSONC and TOML configs in each agent's own dialect), its skills including the shared `~/.agents/skills` library, and its global instruction files with a rough token count.
- **Risky MCP configs**: API keys and tokens written into a config (the value is never printed), remote servers over plain `http://`, remote servers with no credentials configured, commands that are not on `PATH` so the server cannot start, and `npx`/`uvx` packages with no pinned version.
- **Drift**: the same server defined differently in two agents, servers set up in some agents but not others, two different copies of one skill, skills without `name`/`description` frontmatter, and instruction files that differ between agents. Inside an AgentHub checkout, or with `--registry <dir>`, it also compares each agent with the registry.

It never writes a file, starts a server or opens a network connection. `--probe-remote` is the one exception you opt into: it sends a single MCP `initialize` request, with no credentials, to each remote server that has none configured, and reports the ones that answer anyway.

| Option | What it does |
| --- | --- |
| `--json` | Full report as JSON, with secret values redacted |
| `--host codex,cursor` | Only check these agents |
| `--home <dir>` | Inspect another home directory, such as a fixture or a teammate's copied config |
| `--probe-remote` | Check whether remote MCP servers without credentials answer anyway |
| `--strict` | Exit 1 when there is any high-severity finding, for CI |
| `--no-registry` | Compare agents with each other even inside an AgentHub checkout |
| `--verbose` | List every info finding |

`agenthub doctor --help` lists the rest. It needs Node 20+ and runs on Windows, macOS and Linux.

## Keeping them in sync

If you run more than one AI coding agent, you end up with several copies of the same instructions, skills and MCP server settings, and they slowly stop matching. AgentHub keeps one canonical copy, writes it into each agent's own configuration format, and tells you when an agent has drifted from it.

It targets Claude Code, OpenAI Codex, Cursor, Gemini CLI, GitHub Copilot CLI and the other agents listed in [`registry/agents.json`](./registry/agents.json). The sync engine is a set of PowerShell 7 scripts over plain JSON and Markdown. It runs on Windows, macOS (Apple silicon and Intel) and Linux: CI runs `validate`, the `sync` audit and the full test suite on all of them. Each host's paths follow its documented layout per OS, for example `~/.claude` everywhere, Cursor and VS Code settings under `%APPDATA%`, `~/Library/Application Support` or `~/.config`, and Devin under `%APPDATA%\devin` on Windows but `~/.config/devin` on macOS and Linux. A few owner-workstation integrations are Windows-only (see [Platform support](#platform-support)). Nothing is written to an agent's configuration until you run `sync --apply`.

### What it keeps in sync

You describe your setup once, in this repository. AgentHub works out what each host needs.

| You keep | AgentHub writes, per host |
| --- | --- |
| Global policy, as one Markdown file | The host's global instruction file |
| Skills, in `packages/<name>/` | The host's skills directory |
| Plugins | The host's native plugin package where it has one, loose skills and MCP configuration where it does not |
| MCP servers, in `registry/mcps.json` | An entry in the host's own MCP config file |
| Subagents, as `agents/*.agent.md` | Native subagent files for Codex, OpenCode, Gemini CLI and Antigravity |

A host with no documented location for one of these is skipped rather than guessed at.

The registry describes Claude Code, OpenAI Codex, Cursor and Cursor Agent, Gemini CLI, GitHub Copilot CLI, OpenCode, Cline, Amp, Devin, Factory Droid, Grok CLI, Google Antigravity, Warp and VS Code Insiders. Windsurf and OpenCode Desktop are marked unverified.

### Why you can trust it with your agents' config

AgentHub edits files your agents read at startup, so its defaults are cautious.

- **Audit first.** `sync` reports drift and changes nothing. `sync --apply` runs validation first and stops if it fails.
- **Your hand-written files are safe.** A host instruction file is rewritten only if AgentHub's own managed marker is in it. Anything else is reported as `unmanaged` and left alone. Each host is reported as `current`, `drift`, `missing`, `unmanaged` or `skipped`.
- **No secrets in the registry.** MCP entries refer to environment variables or OAuth, never to values. [SECURITY.md](./SECURITY.md) lists what must never be committed.
- **A rehearsal mode.** The sync scripts take `-UserProfile`, which points every read and write at a throwaway home directory. The tests use it, so they cannot touch your real configuration.
- **Unknown stays unknown.** In the registry, `false` means checked and absent, and `null` means not established. Reports keep that distinction instead of rounding it off.
- **Formats come from the vendors.** [`registry/plugin-formats.json`](./registry/plugin-formats.json) names the vendor documentation each host's plugin format was checked against. A host without a verified plugin format gets loose skills and MCP configuration, not an invented format.
- **Private rules stay private.** Your own policy and private packages go in a gitignored overlay (below). On a machine marked as an overlay host, a sync that cannot find the overlay policy fails instead of deploying the public one over it.

AgentHub was built by Sarosh Hussain as the control plane for his own machine. The registry, scripts and tests in this repository are the ones he runs, with his private overlay left out.

## Sync engine quickstart

You need [PowerShell 7+](https://aka.ms/powershell) (`pwsh`), Git, [ripgrep](https://github.com/BurntSushi/ripgrep#installation) (`rg`, used by `validate`) and Python 3.11+ (`python3`, or `py`/`python` on Windows; `sync --apply` parses the TOML it writes for Codex and Grok with `tomllib`). Node 20+ is optional and provides the `npx agenthub` wrapper. The sync engine runs from a clone; the npm package carries only `doctor`.

```bash
git clone https://github.com/shmindmaster/agenthub
cd agenthub

npm install -g .           # optional
npx agenthub init          # local overlay + profile from examples
npx agenthub validate
npx agenthub sync          # read-only drift audit
# npx agenthub sync --apply
```

`init` copies the example overlay and profile into place and writes nothing to any host.

Or, without Node:

```powershell
pwsh -NoProfile -File .\scripts\AgentHub.ps1 init
pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate
pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync
```

Walkthrough: [docs/development/quickstart.md](./docs/development/quickstart.md).

### Watch drift happen without touching your own config

`scripts/AgentHubDemoProfile.ps1` builds a throwaway profile, applies the policy to it, edits one policy line, and shows the audit go from `current` to `drift` and back.

```powershell
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action New
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action EditPolicy
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Remove
```

The sequence and the cases where the script refuses to run are in [docs/runbooks/demo-profile.md](./docs/runbooks/demo-profile.md).

## The personal overlay

Some of what you give your agents should not be public: owner-specific policy, private skill packs, local paths. AgentHub keeps that in `overlays/personal/`, which is gitignored. `init` creates it from [`overlays/personal.example/`](./overlays/personal.example).

- Core never imports an overlay package by default. A capability is private only if its registry row says so.
- `AGENTHUB_OVERLAY=off` loads the public graph only.
- Machine-specific roots go in `agenthub.profile.json`, also gitignored. [`agenthub.profile.example.json`](./agenthub.profile.example.json) is the template.

## Where things live

- `packages/<name>/` holds the canonical capability content.
- `registry/capabilities.json` records ownership and which hosts get each capability.
- `registry/mcps.json` lists the shared MCP servers, with environment or OAuth references and no credential values.
- `registry/agents.json` holds each host's native paths as `{userHome}`, `{localData}` and `{roamingConfig}` templates. [docs/architecture/control-plane-modules.md](./docs/architecture/control-plane-modules.md) explains how they resolve.
- `policy-core.md` and `global-agent-policy.md` are the portable policy that gets compiled into each host's instruction file.
- `.agents/plugins/marketplace.json` is the plugin catalog. `.claude-plugin/marketplace.json` is its Claude-compatible projection.

Runtime output goes under the OS local-data root: `%LOCALAPPDATA%\AgentHub` on Windows, `~/Library/Application Support/AgentHub` on macOS and `${XDG_DATA_HOME:-~/.local/share}/AgentHub` on Linux. Do not commit credentials, customer data or generated media.

## Platform support

| | Windows | macOS (Apple silicon, Intel) | Linux |
| --- | --- | --- | --- |
| `agenthub doctor` (Node 20+) | yes | yes | yes |
| `validate`, `sync` audit, `sync --apply` (PowerShell 7+) | yes | yes | yes |
| Coding-agent dispatch, fleet board, demo profile | yes | yes | yes |
| Test suite in CI | full | full, minus Windows-host features | full, minus Windows-host features |

A host whose config location differs by OS declares the macOS and Linux paths in `platformPaths` in [`registry/agents.json`](./registry/agents.json), with the vendor documentation each was checked against. A Windows install pin (`.exe`, `.cmd`, `AppData`) is never mapped onto another OS; for a CLI that installs onto `PATH`, its command name is looked up there instead.

Windows-only by design, because they depend on Windows facilities with no macOS or Linux equivalent:

- **desktop-evidence** screen capture uses FFmpeg `gdigrab` and GDI. Use browser-evidence for web pages on any OS.
- **RepoWise bounded indexing** caps the indexer's memory with a Windows Job Object; the RepoWise bridge and its updater use the Windows `py` launcher and Task Scheduler.
- **The mobile device lab** drives a VMware Workstation macOS guest and the Android emulator from a Windows host.

[`tests/ci-skip.json`](./tests/ci-skip.json) lists every test CI does not run and why: tests that read the owner's own machine, and the Windows-host features above on macOS and Linux.

## Commands

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All

npm ci                     # doctor's dev tooling: TypeScript checking only
npm test                   # doctor unit and fixture-home tests
npm run typecheck
```

`doctor` lives in `src/doctor/` as dependency-free JavaScript checked by TypeScript (`checkJs`), so `npx` runs it without a build step.

`Check-RepoStandard.ps1` checks the repositories named in `registry/repo-standard.json` against the repository standard. That roster is the author's; edit it, or pass `-ConfigPath`, to check your own.

`npx agenthub export <dir>` writes a stripped copy of the public tree to an empty directory, as a residue audit. It does not push anything.

## Documentation

- [docs/README.md](./docs/README.md) is the map.
- [docs/product/vision.md](./docs/product/vision.md) covers what AgentHub is for and what must never enter this repository.
- [docs/runbooks/sync-and-validate.md](./docs/runbooks/sync-and-validate.md) covers drift audits, deploys and validation.
- [CONTRIBUTING.md](./CONTRIBUTING.md) covers layout and rules for changes.
- [SECURITY.md](./SECURITY.md) covers reporting a vulnerability.
- [LICENSE](./LICENSE) is Apache-2.0.
