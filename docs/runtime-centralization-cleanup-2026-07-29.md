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
- The user-level `TMPDIR` is pinned to `%LOCALAPPDATA%\AgentHub\tmp` so
  POSIX-style agent runtimes cannot materialize `/tmp` as `C:\tmp`.
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
| `C:\cache` | An earlier Pnpm invocation initialized an empty v11 metadata database at 16:42. Windows process-creation telemetry was not retained, so the exact invoking process is an inference rather than an audit fact. | The current Pnpm store and npm cache resolve to `D:\AI-Platform\cache\pnpm` and `D:\AI-Platform\cache\npm`. The recreated root cache was moved intact to `%LOCALAPPDATA%\AgentHub\quarantine\root-cleanup\cache-20260729-164221`; Pnpm, Qwen, and Qoder probes did not recreate it. |
| `C:\tmp` | Codex Desktop's host-owned sandbox runtime creates `/tmp/sessions/<session-id>` as `C:\tmp\sessions`; the original missing-`TMPDIR` attribution was disproved after restart | User and process `TMPDIR` are pinned below `%LOCALAPPDATA%\AgentHub`, but Codex Desktop 26.721.4979 still recreates the root. It remains an explicit platform blocker; see `docs/codex-node-repl-root-temp-blocker-2026-07-30.md`. |
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
- Claude Code loads GitHub and Notion once from enabled HTTP plugins. Canva
  and Descript load once from Claude account connectors. Product Demo Studio
  remains available through eight exact canonical loose skills on Claude, so
  its bundled Descript MCP is not loaded a second time.
- Copilot loads Product Demo Studio and Product Experience Engineering from
  generated AgentHub plugin adapters. The Product Demo adapter is
  skills-only for Copilot because that host does not expose an external
  plugin's bundled MCP through its management surface; one direct remote
  Descript registration supplies the connector without duplication.
- The installed Codex/agent plugin caches contain no persistent local MCP
  command declaration. Claude Desktop's native MCP config contains zero
  servers.
- Claude Desktop's account-installed Desktop Commander plugin was the one
  exception: it eagerly spawned an `npx` MCP process tree when Claude started,
  despite the empty native config. The plugin was disabled through Claude's
  supported Plugins settings. Its two Node workers exited immediately and did
  not respawn during a 20-second observation.
- The final process scan found zero known local MCP workers. Codex Desktop
  retained several idle `node_repl` wrapper processes owned by its tool
  runtime, with one active kernel child; unrelated TypeScript language-server
  and lint workers belonged to another development task. A Qwen CLI tree left
  by a management-surface probe was traced and stopped without touching other
  agents. Across the final five-second sample, the remaining Node/Python set
  consumed 0 CPU-seconds.
- Hosted HTTP MCPs may establish a lightweight client session per coding
  agent, but they do not create one Node or Python server process per agent on
  this machine. Local tools run only when their owning plugin or skill is
  explicitly used, or after a reviewed shared-gateway implementation.
- No AgentHub scheduled task, service, or startup command was found that can
  reapply an older MCP configuration at reboot. The Windows
  `McpManagementService` is present but stopped/manual and is not an AgentHub
  process.

## Verification

- PowerShell 7 with Pester 6.0.1: 104 passed, 0 failed.
- Windows PowerShell 5.1 with Pester 5.6.1: 104 passed, 0 failed.
- Full-access profile distribution lane: 21/21 under each engine, including
  stale-junction recovery, Claude plugin-to-loose-skill transitions, Copilot
  adapter ownership, Qwen native-skill deployment, and signature-gated
  quarantine of the orphan Claude `local-ai-stack` skill.
- Exact managed-skill audit: 411 required host placements and 19 Qoder
  plugin-materialized skill views checked, with 0 missing and 0 content
  mismatches. No AgentHub-managed shadow remains under `~/.agents/skills`.
- Firecrawl plugin validator: passed against the canonical package.
- Managed-file secret audit: 31 current managed files scanned, 0 potential
  inline secrets. The earlier count included 2,162 dead Pester fixture paths
  accumulated in sync state; the state-isolation and fresh-inventory fixes
  remove that false history.
- Sync state now resolves beneath a supplied synthetic user profile instead of
  inheriting the invoking user's live `LOCALAPPDATA`, and apply removes missing
  destinations from the current managed-file inventory.
- The retired `shwiki-context` loose-skill generation has one registry-owned
  signature under `repocontext`; exact historical copies are quarantined while
  same-named user content is preserved.
- JSON, TOML, YAML, plugin manifest, worktree policy, host readiness, and
  second-apply exact-hash checks: passed.
- Registry content hashes normalize text line endings and exclude dependency
  and build artifact directories. The canonical checkout and the task worktree
  now produce identical hashes even when Git materializes different line
  endings or a local `node_modules` tree exists.
- The live full-access checker now derives each host's persisted MCP set from
  `registry/native-connectors.json`, rejects every on-demand local MCP in host
  configuration, and runs under both PowerShell generations without the
  unsupported Windows PowerShell `ConvertFrom-Json -Depth` flag.

The advertised validator now resolves repository-owned canonical paths through
the checkout or worktree being validated while requiring deployed global
instructions to keep pointing at the durable canonical checkout. This prevents
an isolated branch from silently validating another checkout. The ecosystem
validator passes 87/87 under both PowerShell engines, including canonical
content hashes and global policy pointers.

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

The runtime-centralization change is merged. The protected
`C:\Repos\shmindmaster\agenthub` checkout is clean on `main`, the previously
unrelated `local-ai-stack` work was reconciled byte-for-byte, and its original
working state remains recoverable in a named Git stash. Codex's `portfolio`
marketplace now points at the canonical repository, and fleet synchronization
enforces that path.

1. Restart Codex Desktop before relying on the newly named
   `firecrawl-ops@portfolio` skill package in a fresh task. No current process
   depends on the retired bundled Firecrawl runtime.
2. Cursor remains retained-disabled under the provider hold. Qoder has no
   verified public global worktree hook, so AgentHub instructions and the
   stable helper remain its reviewed enforcement path.

## 2026-07-30 runtime correction

- Grok's enabled `chrome-devtools-mcp` plugin duplicated a local MCP outside
  Grok's registered connector contract. It was disabled through
  `grok plugin disable chrome-devtools-mcp`; the plugin is now recorded only
  in Grok's disabled list.
- The already-open Grok process cached the prior enabled state and respawned
  its traced descendants after they were stopped. The persistent
  configuration is corrected, but the current Grok session must be restarted
  before the cached local MCP tree disappears. AgentHub did not terminate the
  Grok parent or unrelated Node processes.
- The live fleet scanner now groups launchers, workers, and watchdogs into one
  logical local-MCP runtime tree, records its owning host, and rejects an
  enabled plugin whose MCP is absent from that host's connector ownership.
- `C:\tmp` was recreated despite correct process and user `TMPDIR` values.
  The supported Codex surfaces expose no Desktop writable-workspace relocation
  control. This is documented as a platform blocker rather than hidden by an
  unsafe workaround.
