# Live coding-agent fleet drift — 2026-07-29

## Outcome

The former validation was registry-scoped and could prove only that AgentHub's
registries and generated files agreed with each other. It did not enumerate
every live host discovery path, active plugin package, MCP configuration,
reparse point, runtime process, or worktree.

`scripts/Test-LiveAgentFleetDrift.ps1` now performs that machine-wide,
read-only comparison. The latest full run inventoried:

| Surface | Live count |
| --- | ---: |
| Registered agents and companion surfaces | 22 |
| Skill/plugin/extension discovery roots | 33 |
| Enabled or installed-observed plugin packages | 58 |
| Host-visible skill records | 941 |
| Persisted MCP configuration surfaces | 19 |
| Registered and native worktree records | 82 |
| Relevant runtime processes | 66 |

The run reported 64 failures, 40 warnings, and 59 passes after root recreation
checks were added. Raw findings intentionally count each affected skill,
plugin requirement, dangling link, and worktree separately. Several raw
findings belong to one underlying remediation incident.

The machine-readable report is:

`%LOCALAPPDATA%\AgentHub\reports\fleet-inventory\latest.json`

## Confirmed active-host drift

| Host | AgentHub-owned or expected state | Actual live state |
| --- | --- | --- |
| Claude Code | Retired skills absent | `~/.claude/skills/agent-fleet-ops` is still visible |
| Codex | One exposure owner per service; one loose skill ID per host | `use-railway` is exposed by both `~/.codex/skills` and `~/.agents/skills`; Context7, Exa, and Tavily each exist as both a direct MCP registration and an installed remote connector package |
| GitHub Copilot CLI | An enabled plugin owns its packaged skills once | The enabled Vercel plugin and `~/.copilot/skills` expose nine duplicate, content-divergent skill IDs |
| Qoder | Product Demo Studio and Product Experience Engineering are plugin-owned | The same packages are also deployed as loose skills, producing 19 duplicate IDs; `product-demo-studio-visual-assets` is content-divergent and the loose copy does not match its canonical owner |
| Grok | Only registered MCP owners | `n8n` remains in `~/.grok/config.toml` without an AgentHub MCP owner |

All other parsed direct MCP sets match their current
`registry/native-connectors.json` ownership contract. The live process scan
found zero known local MCP workers. Normal Codex, Claude/Cowork, language
server, Node REPL, desktop, and agent support processes are inventory records,
not drift.

## Retained and inactive-host drift

- Devin has five required local plugin sources under the deleted
  `~/sh-portfolio-devin/plugins` root: `knowledge-system`,
  `ediscovery-processing`, `use-digitalocean`, `use-elevenlabs`, and `clerk`.
  Its five cached version entries are dangling reparse points. The first two
  plugin names are not current AgentHub capabilities; the last three have
  canonical AgentHub package owners.
- Cursor is retained-disabled and was not launched or probed. Its retained
  configuration exposes 19 duplicate Clerk, DigitalOcean, and ElevenLabs
  skill IDs through both loose and local-plugin surfaces. These are warnings
  until Cursor is reauthorized, not active-runtime failures.
- Windsurf is inactive and its executable remains unresolved. Its retained
  configuration and skills were still inventoried.

## Cross-host ownership drift

Eight unregistered loose skill IDs have content-divergent copies across host
homes:

- `docs-drift`
- `framer`
- `issue-to-pr`
- `portfolio-audit`
- `release-readiness`
- `repo-onboard`
- `use-railway`
- `verify-and-commit`

Twenty additional unregistered loose skill IDs, primarily the shared legal
knowledge skill set, have repeated byte-equivalent copies outside a declared
AgentHub capability owner. Those are ownership warnings rather than content
drift. Host-native and third-party plugin skills are classified separately and
are not failed merely because their names resemble an AgentHub skill.

## Worktree drift and protected WIP

Ten worktree locations violate the `C:\wt\<repo>\<task>` policy:

- Five registered ABACare worktrees remain below
  `Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity`.
  Three contain modified files; two are clean. Several track deleted remote
  branches.
- Five standalone Git repositories remain below `~/.grok/worktrees`.
  One ABACare repository contains three modified files. One SubOps repository
  is one commit ahead of `origin/main`. The other three are clean.

These locations are report-only and protected. The validator never removes,
moves, prunes, checks out, or resets a worktree.

## Root recreation regression

`C:\tmp\sessions` was recreated at 2026-07-29 20:01:35 America/Chicago after
the computer restart. User and process `TMPDIR` both correctly resolve to
`%LOCALAPPDATA%\AgentHub\tmp`, so the original environment fix is insufficient.

The directory structure and timestamps correlate with this Codex Desktop task.
Codex Desktop 26.721.4979 launches `codex-code-mode-host.exe`; the code-mode
execution path is the current attribution because it materializes
POSIX-style `/tmp/sessions` on the current Windows drive despite the correct
temp environment. Windows did not retain a file-creation process event, so
the exact creator PID is an evidence-based inference rather than a retained
kernel audit fact.

The comprehensive checker now fails on every prohibited root artifact as well
as an incorrect user `TMPDIR`.

## Registry omissions corrected

`registry/agents.json` now records nine previously invisible discovery
surfaces:

- shared `~/.agents/skills` discovery for Codex, Gemini, and Cline;
- Amp's instruction and skill paths;
- Devin's skill and plugin paths;
- Copilot's installed-plugin path;
- Antigravity's observed plugin path; and
- Cursor's retained extension path.

This change corrects the inventory authority. It does not remove or alter any
host content.

## Remediation order

1. Correct or isolate Codex Desktop code-mode temp resolution, then remove
   `C:\tmp` and prove it is not recreated by repeated tool calls.
2. Remove the retired Claude `agent-fleet-ops` skill after a final content
   check.
3. Make Qoder's enabled local plugins the sole owner of Product Demo Studio
   and Product Experience Engineering; preserve and review the divergent
   visual-assets copy before removing the loose duplicate.
4. Make the enabled Copilot Vercel plugin the sole owner of its nine duplicated
   skills, after confirming no user-only edits exist in the loose copies.
5. Reconcile Codex's Context7, Exa, and Tavily ownership so each is either a
   direct registered MCP or a remote connector package, never both.
6. Rebuild Devin's local plugin lock from current AgentHub owners and retire
   the two historical plugin names through a backed-up, signature-checked
   cleanup.
7. Preserve and relocate the ten noncompliant worktrees to `C:\wt`, or archive
   them through their owning repositories after branch/WIP review.
8. Assign owners or intentional-native classifications to the unregistered
   loose skills, then converge or remove divergent copies.

