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

Cursor is currently a retained-but-disabled surface. Do not route work to its
IDE agent, local CLI, Cloud/Background Agents, or API until the owner explicitly
reauthorizes it after quota is restored. Re-enabling requires one reviewed change
that sets both Cursor dispatch flags to Boolean `true`, sets
`providerHolds.cursor.active` to Boolean `false`, and updates the provider hold in
`standards/global-agent-policy.md`, followed by `generate`, `sync -Apply`, and
validation. Changing the registry flag alone is intentionally insufficient.
Persistent Cursor API environment variables are removed while the hold is in
force. Long-lived processes can retain an inherited process-scoped copy until
they are restarted; validation reports only the remaining scope, never values.

## Operating model

Claude, Codex, and other personal agent hosts share the policy in [`docs/cross-agent-operating-charter.md`](docs/cross-agent-operating-charter.md) and the stable, client-free memory seed in [`docs/cross-agent-memory-seed.md`](docs/cross-agent-memory-seed.md). Personal capability work is isolated from client systems and uses synthetic fixtures.

- Define one capability owner in `registry/capabilities.json`.
- Expose it through MCP or an existing API first.
- Use the smallest host-native adapter only when a host needs one.
- Keep secrets in environment variables or OAuth flows; never commit them here.

## Retained core

The registry owns seven deployable plugins: `clerk`, `digitalocean-ops`, `elevenlabs-media`, `product-experience-engineering`, `product-demo-studio`, `campaign-production`, and `prompt-os`. `shwiki-context` is the shared read-only portfolio-context skill and MCP control plane.

`product-experience-engineering` is the single owner for making a real workflow useful, coherent, polished, and demo-ready. Its `prepare-product-for-demo` entry skill runs the mandatory pre-production audit, authorized remediation, validation, and revision-bound handoff. Product Demo Studio consumes that handoff; it does not own product remediation.

`product-experience-engineering` and `product-demo-studio` have canonical packages under `packages/handoff-plugins/plugins/`. Claude and Codex use installed native plugins at the canonical manifest versions, Copilot CLI loads both packages through repeated `--plugin-dir` arguments, VS Code Insiders registers both through `chat.pluginLocations`, Qwen uses managed extension junctions, and the remaining registered hosts receive exact sibling skill trees. The distribution script removes duplicate loose copies from native-plugin hosts and retires legacy owners only after exact-signature checks.

Run `powershell.exe -NoProfile -File .\scripts\Apply-FullAccessAgentProfile.ps1 -SkillDistributionOnly -RetireLegacyVideoOwners` to refresh the video capability without rewriting unrelated host settings. Restart open agent sessions afterward so they reload skills and plugin manifests.

`shwiki-context` is the portfolio context control plane. Local stdio (`pnpm --dir C:/Repos/shmindmaster/shwiki mcp:wiki`) is canonical on this workstation and exposes eight read-only tools; the hosted endpoint is a reviewed-snapshot fallback. Capability package: `capabilities/shwiki-context/`. Host auth stays in secret stores; never commit tokens.

Run `pwsh -File .\tests\Validate-AgentEcosystem.ps1 -IncludeGlobalInstructions` before publishing changes. The check uses no network calls and does not inspect or print secret values.

Run `pwsh -File .\tests\Test-HostReadiness.ps1` to report locally installed host clients and required policy pointers without opening a browser, connecting to an MCP server, or reading credentials.

The lean shared MCP set is Context7, Canva, Notion, Playwright, n8n, and ShWiki. OAuth approval is deliberately per host; see `registry/mcp-registrations.json` for status without storing auth material.

Worktree creation, retention, and cleanup are governed by the single shared policy in `docs/worktree-management-policy.md`. Run `scripts/Audit-Worktrees.ps1` for a report-only inventory; cleanup is deliberately separate.
