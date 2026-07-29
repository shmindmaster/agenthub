# Runtime centralization and root cleanup evidence — 2026-07-29

## Outcome

- `C:\wt\<repository>\<task>` is the only approved coding-agent worktree
  pattern. The user environment contract is `AGENTHUB_WORKTREE_ROOT=C:\wt`.
- AgentHub's stable worktree helper is installed under
  `%LOCALAPPDATA%\AgentHub\bin`. Twelve exact generated instruction targets
  are live, and the supported native controls for Claude Code, Gemini,
  Hermes, Copilot, Grok, and Warp are deployed.
- Qwen's eight managed extension junctions now resolve through
  `%LOCALAPPDATA%\AgentHub\runtime\qwen-code\extensions`; broken links to
  `C:\Repos\agenthub` and `C:\Repos\agent-capabilities` were removed from both
  the user extension directory and AgentHub source checkouts.
- The empty legacy directories `~/.codex/worktrees` and
  `C:\wt\agent-capabilities` were removed after content checks. Existing
  worktrees below `C:\wt` were preserved.
- Pnpm's store is `D:\AI-Platform\cache\pnpm`; the on-demand Playwright MCP
  contract pins output to `%LOCALAPPDATA%\AgentHub\runtime\playwright`.
- Firecrawl service ownership remains in `registry/mcps.json`. Its 41-file
  skill package is now the AgentHub-owned
  `packages/portfolio-plugins/firecrawl-ops`, installed in Codex as
  `firecrawl-ops@portfolio`. Neither the source nor installed cache contains
  `.mcp.json`.
- The retired `agent-fleet-ops` user skill, personal Firecrawl plugin
  registration, personal marketplace file, old editable Firecrawl source,
  and both historical `C:\Repos\...\agent-capabilities` paths are absent.
- Historical VS Code Insiders plugin locations below
  `C:\Repos\agent-capabilities` were removed while unrelated user plugin
  locations were preserved. The controller now enforces that migration.
- All explicitly listed obsolete drive-root directories remain absent.
  `C:\wt` is retained by explicit user approval.

## Root artifact attribution and disposition

| Artifact | Evidence-based attribution | Disposition |
| --- | --- | --- |
| `C:\.codex-plugin`, `C:\registry`, `C:\scripts`, `C:\skills`, `C:\product-demo-studio`, `C:\package.js` | Matching timestamps and fixture-shaped content identify an elevated Pester fixture whose test path escaped to the drive root | Fixture construction and path validation corrected; all removed |
| `C:\.playwright-mcp` | A Codex/Playwright screenshot operation used `C:\` as its current directory | Removed; canonical `--output-dir` deployed under AgentHub runtime |
| `C:\cache` | Pnpm `storeDir` | Store moved to `D:\AI-Platform\cache\pnpm`; root directory removed |
| `C:\tmp` | Claude Desktop session paths using `/tmp/...` | Removed; no active process references it |
| `C:\Temp` | Mixed historical use; observed Claude/Cowork tooling and later Codex test output | Required evidence moved to AgentHub reports; root directory removed |
| `C:\wt` | Historical manual worktree fallback | Retained and promoted to the explicitly approved canonical root |

Attribution is based on filesystem timestamps, artifact contents, archived
session/configuration evidence, and traced process ownership. Where Windows
telemetry did not retain the original creator event, the attribution is an
inference rather than a process-audit record.

## Live deployment evidence

- Worktree deployment report:
  `%LOCALAPPDATA%\AgentHub\reports\worktree-policy\deployment-20260729-121905-634.json`
- Pre-convergence backup:
  `%LOCALAPPDATA%\AgentHub\reports\backups\pre-live-convergence-20260729-111945`
- Legacy instruction backup:
  `%LOCALAPPDATA%\AgentHub\reports\backups\legacy-instructions-20260729-122111`
- Firecrawl source backup:
  `%LOCALAPPDATA%\AgentHub\reports\backups\firecrawl-source-20260729-123800`
- Root cleanup manifest:
  `%LOCALAPPDATA%\AgentHub\reports\root-cleanup\2026-07-29-precleanup.json`
- Final all-scope MCP idempotence audit:
  `%LOCALAPPDATA%\AgentHub\sync\drift-reports\drift-20260729-135822.json`
- Managed-file secret audit:
  `%LOCALAPPDATA%\AgentHub\reports\secret-audit\mcp-secret-audit-20260729-final.json`
- Guarded elevated root-file cleanup result:
  `%LOCALAPPDATA%\AgentHub\runtime\remove-root-package.result.json`

The worktree policy checker reports 5 pass, 1 warning, and 0 failures. The
warning is the intentional manual-verification boundary for Claude Desktop;
the user stated that setting was already changed. Host readiness reports
15 registered, 15 installed, and 0 policy failures.

The final MCP audit reports `unchanged` for every mapped active and inactive
host, including Claude, Codex, Qwen, OpenCode, Gemini, Hermes, Copilot,
Antigravity, Grok, Warp, Cline, Qoder, Cursor, Amp, Devin, Factory Droid,
VS Code Insiders, and Windsurf. A later scan of 87 native configuration files
found zero historical root or retired checkout path references. The process
scan found zero historical path references and zero `firecrawl-mcp` process
trees.

## MCP runtime fanout prevention

- All 14 registered MCP contracts are classified by lifecycle: 10 hosted HTTP
  services are `shared-remote`; four local stdio tools (`brave-search`,
  `chrome-devtools`, `playwright`, and `repocontext`) are
  `on-demand-local`.
- `Sync-AgentHub.ps1` never emits an `on-demand-local` launcher into host
  configuration under any scope, including `all`. It also removes stale local
  registrations without broad pruning, so unrelated user-owned remote entries
  remain intact.
- All 19 mapped live MCP config files were scanned after synchronization.
  None contains an AgentHub-registered `on-demand-local` launcher. Codex's
  host-native `node_repl` remains host-owned and starts only for an explicit
  browser or computer-use session.
- Claude Code's installed MCP plugin manifests (GitHub, Notion, and Descript)
  are HTTP-only. The installed Codex/agent plugin caches contain no local MCP
  command declaration. Claude Desktop's native MCP config contains zero
  servers.
- Claude Desktop's account-installed Desktop Commander plugin was the one
  exception: it eagerly spawned an `npx` MCP process tree when Claude started,
  despite the empty native config. The plugin was disabled through Claude's
  supported Plugins settings. Its two Node workers exited immediately and did
  not respawn during a 20-second observation.
- The final process scan found no persistent agent-owned Node or Python MCP
  worker. The one remaining Node process was the current Codex task's
  explicitly invoked, on-demand Computer Use `node_repl` session.
- Hosted HTTP MCPs may establish a lightweight client session per coding
  agent, but they do not create one Node or Python server process per agent on
  this machine. Local tools run only when their owning plugin or skill is
  explicitly used, or after a reviewed shared-gateway implementation.
- No AgentHub scheduled task, service, or startup command was found that can
  reapply an older MCP configuration at reboot. The Windows
  `McpManagementService` is present but stopped/manual and is not an AgentHub
  process.

## Verification

- PowerShell 7 with Pester 5.6.1: 91 passed, 0 failed.
- Windows PowerShell 5.1 with Pester 5.6.1: 91 passed, 0 failed.
- Focused worktree/runtime lanes: 34/34 under each engine.
- Focused MCP determinism lanes: 28/28 under each engine.
- Qwen profile self-healing regression: 12/12 under each engine, with the
  repaired junction asserted against the AgentHub user runtime target.
- Firecrawl plugin validator: passed against the canonical package.
- Managed-file secret audit: 1,309 files scanned, 0 potential inline secrets.
- JSON, TOML, YAML, plugin manifest, worktree policy, host readiness, and
  second-apply exact-hash checks: passed.

The advertised validator intentionally reads absolute canonical-source paths
from `C:\Repos\shmindmaster\agenthub`. Before this branch is integrated it
therefore reports the new Firecrawl source as missing. It also reports the
pre-existing `product-demo-studio` and `browser-toolkit` hash drift from the
protected dirty canonical checkout. The Pester contract correctly treats
those mutable external-state findings as validator evidence rather than test
runner failures; their content hashes were not silently blessed.

## GitHub Actions retirement

AgentHub is a configuration-management control plane and produces no build,
package, release, or deployment artifact. Its only GitHub Actions workflow
duplicated local PowerShell policy validation without producing a deliverable.
The live workflow was disabled without rerunning it, and its workflow and
CI-only wrapper were removed from the repository.

The 21 short failed runs were not PowerShell, build, or deployment failures.
GitHub rejected each sampled job before assigning a runner or creating any
steps because of the account billing or spending-limit state. No DigitalOcean
AgentHub runner was registered, and none is required. The supported gate is
the local validator under both PowerShell 7 and Windows PowerShell 5.1.

## Remaining gates

1. Merge `codex/agenthub-runtime-centralization` into the protected canonical
   checkout only after its unrelated dirty `registry/capabilities.json` and
   `capabilities/local-ai-stack` work is reconciled. Then repoint the Codex
   `portfolio` marketplace from this task worktree to the canonical repository
   and rerun the advertised validator.
2. Restart Codex Desktop before relying on the newly named
   `firecrawl-ops@portfolio` skill package in a fresh task. No current process
   depends on the retired bundled Firecrawl runtime.
3. Cursor remains retained-disabled under the provider hold. Qoder has no
   verified public global worktree hook, so AgentHub instructions and the
   stable helper remain its reviewed enforcement path.
