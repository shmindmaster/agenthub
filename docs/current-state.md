# Current State

What is true of AgentHub now. Keep this page to one screen: replace a line when the fact changes. History is in git and Linear.

## What ships

- **Public core.** `github.com/shmindmaster/agenthub` is the only control-plane repository. Private packages and registry rows live in the overlay beside it, `agenthub-private`; core never imports the overlay.
- **Packages.** `assemblyai`, `browser`, `coding-agent-dispatch`, `funding`, `media-studio`, `mobile-development`, `product`, `research`, `security`. Each version is in the package's `plugin.json`; `registry/capabilities.json` owns the list.
- **Vendor first.** AgentHub ships a plugin only where no vendor marketplace provides one.
- **Plugins only.** `deployLooseSkills` is false, so no loose skills are copied to hosts. `activationPolicy.pluginOnly` in `registry/mcps.json` lists the only direct MCP entries each host may have.

## Hosts

- `scripts/lib/FleetRoles.ps1` and `registry/agents.json` own which hosts are retained or supported. `registry/fleet-profile.json` owns what may be dispatched and why a host is refused.
- Install, refresh and remove commands per host: [runbooks/plugin-deployment.md](./runbooks/plugin-deployment.md).
- Retired, do not restore: Warp, Kiro, Qoder, Hermes, Gemini CLI, Windsurf (now Devin Desktop).
- Cursor imports the plugins enabled in Claude; AgentHub installs no second copy there.

## Retired, do not reintroduce

- RepoWise (SH-4670). Use native source search and committed `openwiki/` pages.
- Local AI on this PC: models, embedders, speech and local gateways.
- Railway, Firecrawl, Supabase, Slack and Chrome DevTools packages or routes.

## Compute and CI

- Heavy work runs on Daytona: `node scripts/daytona-run.mjs --owner <project> -- <command>`.
- Inference gateway: `registry/inference-providers.json` lists its models and hosts; `scripts/daytona-inference` deploys it. `agent-flagship` is intentionally unprovisioned.
- Pull-request CI runs on GitHub-hosted runners (`.github/workflows/ci.yml`). [`ci/codebuild`](./runbooks/codebuild-pr-ci.md) is an unadopted template (CORE-26).
- [`ci/daytona-factory`](../ci/daytona-factory/README.md) builds and records product demos on manual dispatch.

## Known constraints

- Installed and list-verified is not the same as exercised in a fresh host session. Say which one was checked.
- A `Run-AllTests.ps1` hang at `Test-SyncAgentHubRegistryRoot` was seen twice on 2026-08-11 and not since. Run that file alone before treating it as a failure.
- `tests/ci-skip.json` lists the tests that need this PC.

## Verify

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
```
