# Agent Fleet Convergence Status — 2026-07-30

## Decision

AgentHub is the deployed source of truth for the registered agent fleet. Canonical capability,
skill, plugin, MCP, worktree, quarantine, and deployment contracts are converged and regression
tested. The current live configuration verdict is `PASS` with four explicit runtime/activation
warnings: 106 passes and 0 failures. The installed Product Demo Studio package is current at
`1.3.0`; three already-running Claude sessions must restart to unload prior 1.1.x/1.2.0 package
bytes. Product Experience Engineering is current at `1.1.1` on Claude, Codex, Cursor, and Qoder.
Product Demo Studio review and release eligibility remains `PIPELINE_BLOCKED` until an
operator-controlled host receipt signer proves release-grade read-only execution on a supported
host.

## Canonical ownership

- Fleet, host, capability, MCP, connector, and worktree contracts:
  `registry/`
- Product video:
  `packages/handoff-plugins/plugins/product-demo-studio`
- Product experience:
  `packages/handoff-plugins/plugins/product-experience-engineering`
- Browser execution:
  `packages/portfolio-plugins/browser-toolkit`
- Portfolio engineering:
  `capabilities/portfolio-engineering-ops`
- Framer:
  `capabilities/framer`
- External skill ownership and retired-unowned evidence:
  `registry/skill-ownership.json`
- Fleet deployment and live drift detection:
  `scripts/Apply-FullAccessAgentProfile.ps1`,
  `scripts/Sync-ExternalSkills.ps1`, and
  `scripts/Test-LiveAgentFleetDrift.ps1`

## Deployment and deduplication

- All 22 registered agent records are inventoried. Twenty-one executables are installed; Windsurf
  is the intentionally dormant retained adapter. Policy failures: 0.
- The managed profile reconciles the host-appropriate ownership of 10 shared-remote MCP
  contracts across 13 managed configuration hosts.
- MCP configuration is host-native. Shared remote services such as Context7 do not launch a
  local Node or Python worker per host. Local process-based servers remain on demand.
- Product Demo Studio is native on Claude, Codex, Factory, Grok, Qoder, VS Code Insiders, and
  Copilot where the host supports that route. Qwen uses a native extension; Gemini, Antigravity,
  OpenCode, and Codex receive generated host-native role adapters from the same 13 canonical
  agents. Other mapped hosts receive exact loose skills only when that is their documented
  surface. Product Experience Engineering follows its own registry-selected host adapters.
- Product Demo Studio `1.3.0` was reinstalled from canonical AgentHub in Claude, Codex, Factory,
  Grok, and Qoder; the remaining mapped hosts received current generated adapters or exact skills.
- Product Experience Engineering `1.1.1` has matching Claude, Codex, and Cursor manifests. Its
  Cursor local-plugin junction is verified against the canonical source, and the profile fails
  closed if a future Cursor-native package is missing or version-mismatches that manifest.
- Version `1.3.0` requires guided-screencast choreography and maximized useful screen space:
  page-only/native-fullscreen capture, no extraneous browser or OS chrome, real product actions and
  state transitions, visible click cues, at least 50% planned active-region coverage after
  crop/push-in/recomposition, and result-before-spoken-result narration timing.
- Private review delivery is registry-routed to immutable `Review/<candidateId>` packages under
  the approved product OneDrive roots. Packaging requires arbiter `PASS` plus mandatory final
  verifier `PASS`, stages and validates before atomic promotion, refuses overwrite, and records
  the package as review-only with publication approval still pending.
- Stale VS Code Insiders plugin locations pointing to an AgentHub worktree are now removed
  automatically. The live scanner reports zero duplicate canonical skill exposures.
- The trusted external `use-railway` tree is current on all 11 mapped loose-skill hosts.
- Exact known legacy owners are recoverably quarantined. Divergent or unaudited user content
  is preserved and cannot be removed by name alone.
- GitHub-hosted CI was retired. AgentHub has no build, release, or deploy artifact; repository
  validation is local and deterministic.
- Cursor and Cursor Agent are active. The Cursor-specific MCP adapter replaces historical invalid
  fields instead of merging them: the CLI confirms all eight intended shared registrations are
  parsed. Context7, Exa, Firecrawl, and Tavily are ready; OAuth-backed servers await their normal
  host authentication state, and Adobe reports a connection error without preventing
  any other MCP from loading.

## Root and worktree cleanup

The obsolete drive-root artifacts are absent. The empty `C:\tmp\sessions` tree was moved
recoverably to
`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\drive-root\20260730-102545\tmp`.
`C:\wt` remains intentionally because it is the sole approved worktree root. Seven unique or
dirty worktrees/repositories were preserved intact
under:

- `C:\wt\abacare\sh2317-ci-boundary`
- `C:\wt\abacare\sh2317-final`
- `C:\wt\abacare\sh2317-review-findings`
- `C:\wt\abacare\sh2237-rbt-phone-fidelity`
- `C:\wt\abacare\sh2201-agentic-ux-slice`
- `C:\wt\subops\fleet-pass-a-strip-e26`
- `C:\wt\subops\sh1093-correction-history`

The redundant clean Shwiki copy was moved recoverably to:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730\raw\shwiki-local`

Pre-move bundles, dirty patches, and the verified manifest are at:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730`

## Verification

- Full Pester suite: 162 passed, 0 failed, 0 skipped, including the Cursor schema-focused
  regression test.
- Repository validator: 121 passed, 4 warned, 0 failed.
- Host readiness: 22 registered surfaces; 21 executables plus the intentional dormant Windsurf
  adapter; 0 policy failures.
- Full-access profile: passed for 10 shared-remote MCP contracts across 13 managed hosts.
- External skill report: 11 current targets, 0 stale targets.
- Product Demo Studio: 134 contract assertions passed; package and static parity passed for all
  18 registry mappings; Qoder reports 8 skills, 13 agents, and 1 plugin-owned MCP.
- Independent review: no blocker or critical code finding remained after the final safety fixes.
- Final live inventory: 22 agents, 67 plugins, 934 skills, 19 MCP configurations, 76 worktrees,
  and 76 processes. No duplicate local MCP runtime tree or local MCP worker was found.
- Advisory runtime budgets passed: Codex 1,654.6/4,096 MB, Claude 2,675/4,096 MB, language
  servers 944.3/2,048 MB, and local MCP workers 0/1,536 MB. Auto-termination remains disabled.

Final live report:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\reports\fleet-convergence\live-cursor-parity-final-20260730-150345.json`

Live counts: 106 pass, 4 warn, 0 fail.

## Product video review destinations

The machine-level delivery registry is `registry/product-video-delivery.json`. It maps repository
identity, rather than caller-supplied product names, to these existing private review roots:

- `D:\OneDrive - MahumTech\Videos\GentleNext`
- `D:\OneDrive - MahumTech\Videos\Lawli`
- `D:\OneDrive - MahumTech\Videos\LexAlign`
- `D:\OneDrive - MahumTech\Videos\SubOps`
- `D:\OneDrive - MahumTech\Videos\WarrantyGains`
- `D:\OneDrive - MahumTech\Videos\ABACare`
- `D:\OneDrive - MahumTech\Videos\CoLedger`

No review candidate was fabricated during fleet validation. The first real candidate will be
delivered only after the signed independent-review chain passes.

## Remaining holds

1. **Codex root-temp recurrence risk.** `C:\tmp` is currently absent and the final scanner passes.
   Earlier sessions proved that Codex Desktop can recreate it despite supported environment
   controls, and the app still has no verified writable-workspace temp-root setting. Evidence and
   the required vendor-side control are in `docs/codex-node-repl-root-temp-blocker-2026-07-30.md`.
2. **Retired unowned skills — resolved.** Nineteen unique legal/knowledge/issue workflow skills
   referenced unavailable services or conflicting authority. Thirty-eight exact source trees were
   preserved recoverably under
   `C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\retired-unowned-skills\20260730-125557`
   and removed from active host roots.
   Recreation is now a fleet failure; future replacement requires an owned service, authentication,
   provenance, and synthetic fixtures.
3. **Dormant supported host — no drift.** Windsurf remains supported by a retained adapter, but
   its executable is intentionally not installed or expected on this machine. Re-enabling it
   requires a native install and smoke test.
   Its on-disk configuration is reconciled, but it cannot be runtime-smoked on this installation.
4. **Running Claude session freshness.** Installed Claude bytes are current at Product Demo Studio
   `1.3.0`, but PIDs 34008, 38228, and 29780 loaded 1.1.0, 1.1.2, and 1.2.0 respectively. Restart
   Claude before claiming live runtime parity. AgentHub does not terminate open agent sessions
   because that can discard work.
5. **Independent-review execution trust.** Source, deployment, permissions, and static parity are
   verified. Release-grade read-only enforcement is not: no operator-owned
   `AGENTHUB_EXECUTION_HOST_TRUST_CONFIG` is configured. The agent cannot create or access the
   signing private key, so review, arbitration, final verification, and review delivery correctly
   remain `PIPELINE_BLOCKED`. The dormant Windsurf adapter is not runtime-smoked.
