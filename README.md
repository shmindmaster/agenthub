# AgentHub

If you run more than one AI coding agent, you end up with several copies of the same instructions, skills and MCP server settings, and they slowly stop matching. AgentHub keeps one canonical copy, writes it into each agent's own configuration format, and tells you when an agent has drifted from it.

It targets Claude Code, OpenAI Codex, Cursor, Gemini CLI, GitHub Copilot CLI and the other agents listed in [`registry/agents.json`](./registry/agents.json). It is a set of PowerShell scripts over plain JSON and Markdown, and it runs on Windows, macOS and Linux. Nothing is written to an agent's configuration until you run `sync --apply`.

## What it keeps in sync

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

## Why you can trust it with your agents' config

AgentHub edits files your agents read at startup, so its defaults are cautious.

- **Audit first.** `sync` reports drift and changes nothing. `sync --apply` runs validation first and stops if it fails.
- **Your hand-written files are safe.** A host instruction file is rewritten only if AgentHub's own managed marker is in it. Anything else is reported as `unmanaged` and left alone. Each host is reported as `current`, `drift`, `missing`, `unmanaged` or `skipped`.
- **No secrets in the registry.** MCP entries refer to environment variables or OAuth, never to values. [SECURITY.md](./SECURITY.md) lists what must never be committed.
- **A rehearsal mode.** The sync scripts take `-UserProfile`, which points every read and write at a throwaway home directory. The tests use it, so they cannot touch your real configuration.
- **Unknown stays unknown.** In the registry, `false` means checked and absent, and `null` means not established. Reports keep that distinction instead of rounding it off.
- **Formats come from the vendors.** [`registry/plugin-formats.json`](./registry/plugin-formats.json) names the vendor documentation each host's plugin format was checked against. A host without a verified plugin format gets loose skills and MCP configuration, not an invented format.
- **Private rules stay private.** Your own policy and private packages go in a gitignored overlay (below). On a machine marked as an overlay host, a sync that cannot find the overlay policy fails instead of deploying the public one over it.

AgentHub was built by Sarosh Hussain as the control plane for his own machine. The registry, scripts and tests in this repository are the ones he runs, with his private overlay left out.

## Quickstart

You need [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) and Git. Node 18+ is optional and only provides the `npx agenthub` wrapper. AgentHub is not published to npm, so run it from a clone.

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

Runtime output goes under the OS local-data root (`%LOCALAPPDATA%\AgentHub` on Windows). Do not commit credentials, customer data or generated media.

## Commands

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\scripts\Sync-AgentHub.ps1 -Audit -Validate
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
```

`Check-RepoStandard.ps1` checks the repositories named in `registry/repo-standard.json` against the repository standard. That roster is the author's; edit it, or pass `-ConfigPath`, to check your own.

`npx agenthub export <dir>` writes a stripped copy of the public tree to an empty directory, as a residue audit. It does not push anything.

## Documentation

- [docs/README.md](./docs/README.md) is the map.
- [docs/product/vision.md](./docs/product/vision.md) covers what AgentHub is for and what must never enter this repository.
- [docs/runbooks/sync-and-validate.md](./docs/runbooks/sync-and-validate.md) covers drift audits, deploys and validation.
- [CONTRIBUTING.md](./CONTRIBUTING.md) covers layout and rules for changes.
- [SECURITY.md](./SECURITY.md) covers reporting a vulnerability.
- [LICENSE](./LICENSE) is Apache-2.0.
