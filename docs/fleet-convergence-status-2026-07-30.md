# Agent Fleet Convergence Status — 2026-07-30

## Decision

AgentHub is the deployed source of truth for the registered agent fleet. Canonical capability,
skill, plugin, MCP, worktree, quarantine, and deployment contracts are converged and regression
tested. The live machine verdict remains `BLOCKED` by one Codex Desktop platform issue:
the active application recreates and uses `C:\tmp`.

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
- External skill ownership and preserve-pending evidence:
  `registry/skill-ownership.json`
- Fleet deployment and live drift detection:
  `scripts/Apply-FullAccessAgentProfile.ps1`,
  `scripts/Sync-ExternalSkills.ps1`, and
  `scripts/Test-LiveAgentFleetDrift.ps1`

## Deployment and deduplication

- All 15 registered hosts are installed; policy failures: 0.
- The managed profile exposes 10 global MCP contracts across 13 managed hosts.
- MCP configuration is host-native. Shared remote services such as Context7 do not launch a
  local Node or Python worker per host. Local process-based servers remain on demand.
- Product Demo Studio is native on Codex, Qoder, VS Code Insiders, and Copilot where the host
  supports that route; Qwen uses its native extension; other mapped hosts receive exact loose
  skills. Product Experience Engineering follows the same registry-selected host adapters.
- The stale Product Demo Studio Codex cache was reinstalled from canonical AgentHub.
- Stale VS Code Insiders plugin locations pointing to an AgentHub worktree are now removed
  automatically. The live scanner reports zero duplicate canonical skill exposures.
- The trusted external `use-railway` tree is current on all 11 mapped loose-skill hosts.
- Exact known legacy owners are recoverably quarantined. Divergent or unaudited user content
  is preserved and cannot be removed by name alone.
- GitHub-hosted CI was retired. AgentHub has no build, release, or deploy artifact; repository
  validation is local and deterministic.
- Cursor was not launched or probed. Its provider hold and fail-closed launch shims remain active.

## Root and worktree cleanup

The obsolete drive-root artifacts are absent. `C:\wt` remains intentionally because it is the
sole approved worktree root. Seven unique or dirty worktrees/repositories were preserved intact
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

- Full Pester suite: 160 passed, 0 failed, 0 skipped.
- Repository validator: 79 passed, 0 warned, 0 failed.
- Host readiness: 15 registered, 15 installed, 0 optional missing, 0 policy failures.
- Full-access profile: passed for 10 global MCPs across 13 managed hosts.
- External skill report: 11 current targets, 0 stale targets.
- Product Demo Studio parity: 18 current registry mappings; static contract parity passed.
- Independent review: no blocker or critical code finding remained after the final safety fixes.
- Apply was run twice successfully; the second run made no native plugin replacements.

Final live report:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\reports\fleet-convergence\live-final-20260730.json`

Live counts: 72 pass, 79 warn, 1 fail.

## Remaining holds

1. **`C:\tmp` — FAIL.** The active Codex Desktop runtime recreates and uses this root. The
   supported environment controls already redirect user and agent temporary output into
   AgentHub, but Codex Desktop has no verified writable-workspace temp-root setting. Evidence
   and the safe next gate are in `docs/codex-node-repl-root-temp-blocker-2026-07-30.md`.
2. **Preserve-pending skills — 76 WARN exposures.** Nineteen unique legal/knowledge skill
   contracts are byte-verified and deliberately preserved on four hosts. Promotion or deletion
   is blocked until service ownership, authentication, provenance, and synthetic fixtures exist.
3. **Grok current session — 1 WARN.** Two cached `chrome-devtools-mcp` runtime trees own 12
   processes. Persistent Grok configuration is disabled; restart Grok to clear this already-open
   session. No unrelated process tree was terminated.
4. **Retained inactive hosts — 2 WARN.** Factory's executable is retained but not currently
   resolved; Windsurf is retained without a discovered executable. Neither is an active drift.
5. **Live agent execution parity.** Source, deployment, permission, and static parity are
   verified. Cross-host prompt execution is not claimed: Cursor is held, inactive hosts cannot be
   smoked, and release-grade native read-only enforcement requires a signed live deployment
   report.
