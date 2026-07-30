# Product-video system consolidation — 2026-07-30

Successor to `product-video-system-inventory-2026-07-29.md`. That inventory established the
disposition; this record states what was changed, what was proven, and what is still open.

## Verdict unchanged

AgentHub `handoff/product-demo-studio` is the single canonical owner of the product-video agent
system: agents, skills, prompts, schemas, tool routing, permissions, quality standards, evidence
requirements, release policy, and version metadata. Product repositories keep repository-native
capture and render pipelines and conform their evidence to the canonical contract. No product repo
imports the plugin at runtime, and none should.

Re-verified on this date by an independent filesystem sweep of all twelve `C:/Repos/shmindmaster`
repositories, every agent home on this machine, and `agenthub/generated`, `capabilities`, `roles`,
`adapters`, and `templates`. Findings matched the 2026-07-29 inventory: six repository-native
pipelines (ABACare, Sabhi, CrewScore, Lawli, Verigence, SubOps), two dormant scaffolds (LexAlign,
WarrantyGains), one non-implementation (Repocontext), two removed systems (CoLedger, GentleNext).
Every other `product-demo-studio*` tree on this machine is a host distribution artifact of the one
canonical source, not an independent fork. Three unrelated third-party video skills exist
(HeyGen avatar video, Figma video-interaction-mapper, quickdesign UGC/upscale); they are different
capabilities and are not part of this consolidation.

## Defect fixed: the canonical evidence contract was unsatisfiable

`schemas/evidence-package.schema.json` requires all fifteen deterministic report types.
`policy/product-video-policy.json` allowed `motionAnalysis` from exactly one generator,
`product-demo-studio-technical-checks`, and `sceneBoundaries` from that generator or
`repository-native-playwright`. The implementation of that generator, `scripts/technical-checks.mjs`,
emitted only five report types and never emitted either of those two.

With `unregisteredGeneratorDecision: PIPELINE_BLOCKED` and `manualPassAllowed: false`, no repository
could assemble a valid evidence package, so `scripts/preflight.mjs` was unreachable for every real
candidate and the four-reviewer chain had never been exercised against one. This was a correctness
defect, not a policy preference.

`technical-checks.mjs` now emits `sceneBoundaries` and `motionAnalysis` from data it already
computes (scene-boundary frame extraction; freeze, duplicate, and decode-integrity measurements).
Contract tests cover it: 124 assertions, 0 failures. Commit `19445b0`.

## Drift prevention added

Two real drift channels were open and are now closed or visible.

1. **Registry content hash.** After `19445b0` the registered `contentHash` for
   `product-demo-studio` no longer matched its `hashBasis`, and no Pester test caught it — the live
   registry hash was asserted only for `framer` and `portfolio-engineering-ops`.
   `tests/Validate-AgentEcosystem.ps1` does check every capability, and it went red
   (`fail=1`, `content hash drifted`) then green (`pass=79 fail=0`) once the hash was corrected.
   The gate was real; it simply had not been run. Run it on every canonical change.

2. **Deployed host copies.** Host installs are pinned by version directory, so a content change
   without a version change never propagates and nothing detected the divergence. The canonical
   package is now `1.1.1` (patch: the missing reports), and
   `tests/Validate-AgentEcosystem.ps1` gained a deployment-freshness gate that compares each
   deployed tree against canonical using the same CRLF-normalizing hash the registry uses, and
   flags a version-pinned cache directory whose name no longer matches the canonical version.
   Absent hosts are skipped rather than failed. Commit `25230cc`.

Initial post-commit state: `pass=83 warn=0 fail=5`. All five failures were genuine, correctly detected stale
deployments of `product-demo-studio` — Claude and Codex caches still pinned to `1.1.0`, and Grok's
hash-named install tree content-drifted. `product-experience-engineering` passes on the same hosts,
which is the green control proving the gate discriminates rather than always failing.

Coverage limits, deliberate at this snapshot: Copilot and VS Code Insiders are not covered because
their local plugin-cache conventions could not be verified against a real install on this machine;
Qwen-code is excluded because its junction mirrors only a skills-and-agents subset; Cursor was
excluded under the then-active provider hold and was not probed.

## Later same-day convergence

The stale Product Demo Studio installs were upgraded through their official host flows to `1.3.1`.
Product Experience Engineering was advanced to `1.1.1` with a matching native Cursor manifest.
Cursor was reauthorized by the owner and its global MCP adapter was corrected to emit the strict
Cursor remote schema; `cursor-agent mcp list` now parses all eight intended shared registrations.
The current ecosystem validation result is `pass=121 warn=4 fail=0`; the warnings are three
already-running Claude processes with older package bytes and the deliberately absent,
operator-owned execution-receipt trust configuration. See
`fleet-convergence-status-2026-07-30.md` for the current inventory and restart requirement.

## Canonical update process

Edit canonical source, bump the capability version, recompute the registry hash, run the package
validators, run the ecosystem validator, then re-deploy hosts. AgentHub deliberately does not
auto-reinstall native plugins — `Apply-FullAccessAgentProfile.ps1` throws on an enabled-but-stale
native plugin rather than writing into a host's plugin cache. Reinstalling is the host's own flow.

## Notion

`prompt.produce-demo-video.v4` / "Produce Demo Video" 5.0.0 instructed agents not to rely on
"approval gates, claim ledgers, or separate review ceremonies" — the direct inverse of the deployed
release contract, and the last competing video workflow in the portfolio. It is superseded by
version 6.0.0, which carries no competing workflow body: it routes to this capability, states the
sequencing, roles, evidence contract, and release policy, and records that the only human gate is
external publication. Properties were corrected to match reality (`Approval Gates: Lead`,
`Requires Approval: yes`, `Validation Status: Both`, content hash recomputed).

## Linear

* `SH-1899` and `SH-2064` described the SubOps pipeline in terms of a `studio/**` tree deleted from
  `main` by `3b227fdc`. Both descriptions now name the real capture, render, gate, and evidence
  paths, and record what was delivered on this date.
* `SH-2430` opened for the one genuine blocker below.
* `SH-2057` remains open for a CoLedger video system removed by `ef27d210`. It is another product's
  backlog and was not touched here; close or re-scope it during an authorized CoLedger task.

## Open blocker

The canonical reviewer, arbiter, and final-verifier roles require host-enforced read-only isolation
**and a host-signed execution receipt**. `AGENTHUB_EXECUTION_HOST_TRUST_CONFIG` is unset and no trust
registry or key material exists anywhere in AgentHub. Every reviewer body therefore returns
`MALFORMED_INPUT` and the run routes to `PIPELINE_BLOCKED`. This is correct fail-closed behavior.

It cannot be resolved by an agent: `agentsMayAuthorExecutionReceipts` is false, and an agent that
generated the key pair, wrote the trust registry, and signed its own receipts would satisfy the file
format while destroying the property the gate exists to provide. Provisioning is operator work —
see `SH-2430`.

Until then, product repositories clear internal delivery through their own automated gates. SubOps'
`pnpm qa:review-demo-video` (51 deterministic checks) is the designated example and is currently
PASS at revision `f05d5b24`.
