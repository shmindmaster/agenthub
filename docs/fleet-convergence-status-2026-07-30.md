# Agent Fleet Convergence Status — 2026-07-30

## Decision

AgentHub is the deployed source of truth for the registered agent fleet. Canonical capability,
skill, plugin, MCP, worktree, quarantine, and deployment contracts are converged and regression
tested. The 2026-07-31 live configuration verdict is `PASS`: 106 passes, 0 warnings, and 0 failures,
with zero local MCP runtime trees after task-scoped cleanup.
The current Product Demo Studio contract and live native installations are `1.5.3`. Product Experience Engineering
was current at `1.1.2` on Claude, Codex, Cursor, and Qoder.
Product Demo Studio now uses automated acceptance, iterative remediation, and a mandatory terminal
independent verifier. Native read-only roles record plain operational receipts; no signer, trust
registry, key, broker, resident service, or intermediate human approval is required.

## Canonical ownership

- Fleet, host, capability, MCP, connector, and worktree contracts:
  `registry/`
- Product video:
  `packages/handoff-plugins/plugins/product-demo-studio`
- Product experience:
  `packages/handoff-plugins/plugins/product-experience-engineering`
- Browser execution:
  `capabilities/browser-toolkit`
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
- The managed profile reconciles shared remote MCP contracts across managed profile hosts.
  Chrome DevTools MCP is task-scoped and removed from all persisted host configurations.
- MCP configuration is host-native. Shared remote services such as Context7 do not launch a
  local Node or Python worker per host. All local process-based servers, including Chrome DevTools,
  remain on demand and are owned only for the active diagnostic task.
- Browser Toolkit `0.2.3` prefers host-native browser tooling and retains
  `npx -y chrome-devtools-mcp@latest` only as a task-scoped fallback; Antigravity may use its documented built-in-browser URL.
  Qoder's duplicate marketplace Chrome plugin is disabled; its unrelated plugins are preserved.
- Product Demo Studio is native on Claude, Codex, Factory, Grok, Qoder, VS Code Insiders, and
  Copilot where the host supports that route. Qwen uses a native extension; Gemini, Antigravity,
  OpenCode, and Codex receive generated host-native role adapters from the same 13 canonical
  agents. Other mapped hosts receive exact loose skills only when that is their documented
  surface. Product Experience Engineering follows its own registry-selected host adapters.
- Product Demo Studio `1.5.3` is deployed to the current native host installations; package and
  ecosystem validators compare deployed bytes to canonical source.
- Product Experience Engineering `1.1.2` has matching Claude, Codex, and Cursor manifests. Its
  Cursor local-plugin junction is verified against the canonical source, and the profile fails
  closed if a future Cursor-native package is missing or version-mismatches that manifest.
- Version `1.5.3` requires guided-screencast choreography and maximized useful screen space:
  page-only/native-fullscreen capture, no extraneous browser or OS chrome, real product actions and
  state transitions, visible click cues, at least 50% planned active-region coverage after
  crop/push-in/recomposition, and result-before-spoken-result narration timing.
- Private review delivery is registry-routed to immutable `Review/<candidateId>` packages under
  the approved product OneDrive roots. Packaging requires arbiter `PASS` plus mandatory final
  verifier `PASS`, stages and validates before atomic promotion, refuses overwrite, and records
  the package as review-only. External publication is a separate consequential action and occurs
  only when the task explicitly authorizes it; it is not an intermediate production approval gate.
- Stale VS Code Insiders plugin locations pointing to an AgentHub worktree are now removed
  automatically. The live scanner reports zero duplicate canonical skill exposures.
- The trusted external `use-railway` tree is current on all 11 mapped loose-skill hosts.
- Exact known legacy owners are recoverably quarantined. Divergent or unaudited user content
  is preserved and cannot be removed by name alone.
- GitHub-hosted CI was retired. AgentHub has no build, release, or deploy artifact; repository
  validation is local and deterministic.
- Cursor and Cursor Agent are active. The Cursor-specific MCP adapter replaces historical invalid
  fields instead of merging them: the current config persists only registry-selected shared remote
  registrations. Chrome DevTools remains task-scoped. Context7, Exa, Firecrawl, and Tavily are ready; OAuth-backed servers await their normal
  host authentication state, and Adobe reports a connection error without preventing
  any other MCP from loading.

## Root and worktree cleanup

The obsolete drive-root artifacts are absent. This Codex Desktop session recreated an empty
`C:\tmp\sessions\<session-id>` tree despite the correct process and user `TMPDIR`; it was moved
recoverably to
`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\drive-root\20260730-171650\tmp`.
The upstream package smoke and final live audit did not recreate it.
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

- Chrome/registry/profile focused Pester suite: 76 passed, 0 failed, 0 skipped. The final
  live-drift regression rerun passed 9/9.
- Repository ecosystem validator: 97 passed, 0 warned, 0 failed.
- Host readiness: 22 registered surfaces; 21 executables plus the intentional dormant Windsurf
  adapter; 0 policy failures.
- Full-access profile: passed for 10 shared remote MCP contracts across all 18 supported host
  configurations.
- External skill report: 11 current targets, 0 stale targets.
- Product Demo Studio: 168 contract assertions passed; package and static parity passed for all
  18 registry mappings; Qoder reports 8 skills, 13 agents, and 1 plugin-owned MCP.
- Independent review: no blocker or critical code finding remained after the final safety fixes.
- Final live inventory found 106 passing checks, 0 warnings, and 0 failures. No duplicate
  configured MCP ownership or local MCP runtime tree remained. Claude and Codex user-installed extra plugins are preserved as host-private
  extensions and are intentionally outside fleet parity and cross-host deployment.
- All advisory runtime budgets passed. Automatic broad process termination remains disabled;
  task-scoped launchers own and close only their exact process trees.

Final live report:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\reports\fleet-inventory\agenthub-marketplace-final-20260730.json`

Live counts: 106 pass, 2 warn, 0 fail.

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
delivered only after the validated independent-review chain passes.

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
4. **Independent-review execution evidence.** Reviewer, arbiter, and final-verifier work uses the
   host's native restricted role/context and records a plain operational receipt. Missing or
   writable contexts route `PIPELINE_BLOCKED`; receipt text is not a security attestation. No
   trust configuration, signing key, broker, or resident process is required. The dormant
   Windsurf adapter is not runtime-smoked.
