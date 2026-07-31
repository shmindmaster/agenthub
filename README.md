# Agent Capabilities

This repository is the source of truth for reusable agent capabilities and their host-native adapters. It does not duplicate capability logic or copy credentials. Native plugins are used where the host supports a verified local package; otherwise the same canonical skills are deployed to the host's documented global skill path.

## Fleet control plane

The repository also compiles shared policy into independently usable host-native files:

- `registry/installations.json` inventories every retained CLI, IDE, desktop, headless, and companion surface.
- `standards/` owns global policy, project coordination, autonomy semantics, and Windows-first rules.
- `roles/` owns the common scout, implementer, reviewer, and verifier contracts; `registry/role-mappings.json` maps existing specialized agents without deleting them.
- `profiles/` defines interactive, repository-autonomous, and machine-maintenance authorization boundaries.
- `templates/` and `generated/` produce native instructions. Authentication, sessions, caches, memories, and runtime databases stay host-local.

Use the central utility from this repository:

```powershell
.\scripts\agentctl.ps1 inventory
.\scripts\agentctl.ps1 evaluate
.\scripts\agentctl.ps1 generate
.\scripts\agentctl.ps1 sync          # dry run
.\scripts\agentctl.ps1 sync -Apply   # managed instruction files only
.\scripts\agentctl.ps1 validate
.\scripts\agentctl.ps1 drift
.\scripts\agentctl.ps1 cleanup       # always report-only
```

`inventory`, `evaluate`, `validate`, `drift`, and `cleanup` are side-effect-free by default. Add `-WriteReport` only when a persisted local report is needed. `generate` and `sync` are the explicit configuration-writing commands; `sync` remains a dry run unless `-Apply` is supplied. `cleanup` never removes an agent or configuration. Exact candidates require a separately authorized and validated maintenance action.

Cursor IDE, Cursor Agent CLI, Cloud/Background Agents, and API dispatch are
active following explicit owner reauthorization on 2026-07-30. Both strict
Boolean dispatch flags are `true` and the separate provider hold is `false`.
Cursor receives the same canonical capability, MCP-ownership, worktree, review,
and drift contracts as the other supported hosts. Availability checks must use
read-only account or local configuration evidence rather than consuming a paid
agent run merely as a probe.

## Operating model

Claude, Codex, and other personal agent hosts share the policy in [`docs/cross-agent-operating-charter.md`](docs/cross-agent-operating-charter.md) and the stable, client-free memory seed in [`docs/cross-agent-memory-seed.md`](docs/cross-agent-memory-seed.md). Personal capability work is isolated from client systems and uses synthetic fixtures.

- Define one capability owner in `registry/capabilities.json`.
- Expose it through MCP or an existing API first.
- Use the smallest host-native adapter only when a host needs one.
- Keep secrets in environment variables or OAuth flows; never commit them here.

## Retained core

The registry owns eleven canonical capabilities: eight plugin capabilities (`clerk`, `firecrawl-ops`, `use-digitalocean`, `use-elevenlabs`, `product-experience-engineering`, `product-demo-studio`, `use-campaign-production`, and `use-prompt-os`), the `repocontext` read-only portfolio-context skill and MCP, the Codex-only `local-ai-stack` skill for the `D:\AI-Platform` runtime, and the `browser-toolkit` skills, MCP, and host adapters. `firecrawl-ops` is a skills-only plugin; the Firecrawl service remains owned by `registry/mcps.json`.

`product-experience-engineering` is the single owner for making a real workflow useful, coherent, polished, and demo-ready. Its `prepare-product-for-demo` entry skill runs the mandatory pre-production audit, authorized remediation, validation, and revision-bound handoff. Product Demo Studio consumes that handoff; it does not own product remediation.

`product-experience-engineering` and `product-demo-studio` have canonical packages under `packages/handoff-plugins/plugins/`. Claude and Codex use installed native plugins at the canonical manifest versions, Copilot CLI loads both packages through repeated `--plugin-dir` arguments, VS Code Insiders registers both through `chat.pluginLocations`, Qwen uses managed extension junctions, and the remaining registered hosts receive exact sibling skill trees. The distribution script removes duplicate loose copies from native-plugin hosts and retires legacy owners only after exact-signature checks.

Codex exposes all eight AgentHub-owned plugins through one repository-level marketplace, [`AgentHub`](.agents/plugins/marketplace.json). The physical package folders remain organized by capability implementation, but they are not separate Codex products or marketplace authorities. The legacy Codex-facing `handoff` and `portfolio` registrations must not be restored.

Run `powershell.exe -NoProfile -File .\scripts\Apply-FullAccessAgentProfile.ps1 -SkillDistributionOnly -RetireLegacyVideoOwners` to refresh the video capability without rewriting unrelated host settings. Restart open agent sessions afterward so they reload skills and plugin manifests.

`repocontext` is the portfolio context control plane. Its local stdio server (`pnpm --dir C:/Repos/shmindmaster/repocontext mcp:serve`) is retained as an on-demand, skill-owned tool and is never written into fleet host configuration. The private Streamable HTTP registration remains deployment-pending until its paid production resource is authorized and passes the authenticated remote contract. Capability package: `capabilities/repocontext/`. Host auth stays in secret stores; never commit tokens.

## Validation policy

AgentHub is a configuration-management control plane. It does not produce a build, package, release, or deployment artifact, and GitHub Actions runs on GitHub-hosted `ubuntu-latest` runners (`.github/workflows/validate.yml`) plus local commands. The dedicated DigitalOcean droplet that used to host these runners is retired.

Validate changes locally in both supported PowerShell engines:

```powershell
pwsh -NoProfile -File .\tests\Validate-AgentEcosystem.ps1
powershell.exe -NoProfile -File .\tests\Validate-AgentEcosystem.ps1
```

Add `-IncludeGlobalInstructions` before publishing changes that affect generated host policy. That mode now runs the comprehensive live-fleet drift gate as well as the registry checks. It compares every registered agent with observed loose-skill, active-plugin, MCP-configuration, executable, reparse-point, runtime-process, and worktree surfaces. Normal agent runtimes, Claude Cowork, language servers, and host-owned support processes are inventoried but are not treated as drift.

Run the live comparison directly when diagnosing a workstation:

```powershell
pwsh -NoProfile -File .\scripts\Test-LiveAgentFleetDrift.ps1 `
  -ReportPath "$env:LOCALAPPDATA\AgentHub\reports\fleet-inventory\latest.json"
```

The live validator uses no network calls, never launches a coding-agent provider, does not mutate agent configuration or worktrees, and redacts credential-shaped command-line arguments in its optional report.

Run `pwsh -File .\tests\Test-HostReadiness.ps1` to report locally installed host clients and required policy pointers without opening a browser, connecting to an MCP server, or reading credentials.

MCP ownership is host-aware. Installed plugins and native connectors suppress duplicate direct registrations. Hosted HTTP services are referenced remotely, so opening several agents does not create one local Node or Python server per agent. Playwright, RepoContext, and Brave Search remain on-demand and are never persisted by fleet sync. Chrome DevTools MCP is the explicit local exception: every supported host receives the upstream README-native registration, so each concurrent host may own one local stdio worker after that host activates the server. Docker MCP Gateway has an installed, partial POC: Linear and Context7 passed, Firecrawl's custom remote snapshot passed bearer-authenticated discovery, and Notion still needs OAuth. Generation remains disabled until the one shared production profile passes. Container-backed catalog servers remain blocked on this Windows host by missing `socat`. See `registry/native-connectors.json`, `registry/gateway-profiles.json`, and [`docs/mcp-ownership-2026-07-24.md`](docs/mcp-ownership-2026-07-24.md).

Worktree creation, retention, and cleanup are governed by the single shared policy in `docs/worktree-management-policy.md`; `registry/worktree-roots.json` records current host-specific enforcement. `C:\wt\<repo>\<task>` is the sole user-created root. `scripts\New-AgentHubWorktree.ps1` supports both the Claude Code `WorktreeCreate` stdin contract and manual `-Cwd` / `-Name` invocation. `scripts\Install-WorktreePolicy.ps1` deploys the stable helper, documented opt-out settings, Claude hook, and Warp Tab Config after backup; `scripts\agentctl.ps1 sync -Apply` deploys managed global instructions with conflict protection. Run `scripts\Audit-Worktrees.ps1` for report-only inventory; cleanup is separate and legacy roots are migration-detection only.

The full-access profile also pins the user-level `TMPDIR` to
`%LOCALAPPDATA%\AgentHub\tmp`. This prevents POSIX-style `/tmp` paths used by
coding-agent runtimes from materializing as a user-created `C:\tmp` directory
on Windows.
