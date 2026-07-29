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
- Pnpm's store is `D:\AI-Platform\cache\pnpm`; Playwright MCP output is pinned
  to `%LOCALAPPDATA%\AgentHub\runtime\playwright` for every active MCP host.
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
| `C:\.codex-plugin`, `C:\registry`, `C:\scripts`, `C:\skills`, `C:\product-demo-studio`, `C:\package.js` | Matching timestamps and fixture-shaped content identify an elevated Pester fixture whose test path escaped to the drive root | Fixture construction and path validation corrected; all removed except `C:\package.js` |
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
- Final MCP idempotence audit:
  `%LOCALAPPDATA%\AgentHub\sync\drift-reports\drift-20260729-130205.json`
- Managed-file secret audit:
  `%LOCALAPPDATA%\AgentHub\reports\secret-audit\mcp-secret-audit-20260729-final.json`

The worktree policy checker reports 5 pass, 1 warning, and 0 failures. The
warning is the intentional manual-verification boundary for Claude Desktop;
the user stated that setting was already changed. Host readiness reports
15 registered, 15 installed, and 0 policy failures.

The final MCP audit reports `unchanged` for Claude, Codex, Qwen, OpenCode,
Gemini, Hermes, Copilot, Antigravity, Grok, Warp, Cline, and Qoder. A later
scan of 87 native configuration files found zero historical root or retired
checkout path references. The process scan found zero historical path
references and zero `firecrawl-mcp` process trees.

## Verification

- PowerShell 7 with Pester 5.6.1: 86 passed, 0 failed.
- Windows PowerShell 5.1 with Pester 5.6.1: 86 passed, 0 failed.
- Focused worktree/runtime lanes: 34/34 under each engine.
- Focused MCP determinism lanes: 28/28 under each engine.
- Firecrawl plugin validator: passed against the canonical package.
- Managed-file secret audit: 1,249 files scanned, 0 potential inline secrets.
- JSON, TOML, YAML, plugin manifest, worktree policy, host readiness, and
  second-apply exact-hash checks: passed.

The advertised validator intentionally reads absolute canonical-source paths
from `C:\Repos\shmindmaster\agenthub`. Before this branch is integrated it
therefore reports the new Firecrawl source as missing. It also reports the
pre-existing `product-demo-studio` and `browser-toolkit` hash drift from the
protected dirty canonical checkout. The Pester contract correctly treats
those mutable external-state findings as validator evidence rather than test
runner failures; their content hashes were not silently blessed.

## Remaining gates

1. `C:\package.js` is the sole remaining forbidden root artifact. Its High
   Mandatory Integrity label prevents deletion from the current
   medium-integrity Codex process. The guarded removal script is
   `%LOCALAPPDATA%\AgentHub\runtime\remove-root-package.ps1`; it requires one
   elevated execution.
2. Merge `codex/agenthub-runtime-centralization` into the protected canonical
   checkout only after its unrelated dirty `registry/capabilities.json` and
   `capabilities/local-ai-stack` work is reconciled. Then repoint the Codex
   `portfolio` marketplace from this task worktree to the canonical repository
   and rerun the advertised validator.
3. Restart Codex Desktop before relying on the newly named
   `firecrawl-ops@portfolio` skill package in a fresh task. No current process
   depends on the retired bundled Firecrawl runtime.
4. Cursor remains retained-disabled under the provider hold. Qoder has no
   verified public global worktree hook, so AgentHub instructions and the
   stable helper remain its reviewed enforcement path.
