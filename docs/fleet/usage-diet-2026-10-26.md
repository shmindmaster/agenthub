# Claude Code usage diet — 2026-10-26

Record of what a Claude Code session (Desktop Code tab and CLI) paid before
doing any work, what was cut on 2026-10-26, and how to undo each change.
Method and evidence rules follow [context-reduction.md](./context-reduction.md).

All changes are reversible, apply to **new** sessions only, and leave running
sessions untouched. Nothing was uninstalled, disconnected or deleted.

## Measurements

Fresh `claude -p "/context"` in the CLI (Git Bash needs `MSYS_NO_PATHCONV=1`,
or the slash is rewritten into a path). `/context` totals exclude the deferred
tool-name list, which is estimated separately below.

| Startup context (CLI, fresh session) | Before | After | Change |
| --- | ---: | ---: | ---: |
| `C:\Repos\shmindmaster\agenthub` | 79.6k | 68.4k | −11.2k (−14%) |
| `C:\Repos\musa-dev-team\duckie-app` | 123.6k | 109.9k | −13.7k (−11%) |

| Category (duckie-app) | Before | After |
| --- | ---: | ---: |
| System prompt + system tools | 19.8k | 19.7k |
| MCP tools loaded up front | 16.3k | 10.6k |
| MCP server instructions | 16.0k | 14.7k |
| Memory files (CLAUDE.md chain, rules, MEMORY.md) | 60.1k | 53.7k |
| Skills listing | 9.9k | 9.9k |
| Custom agents | 1.4k | 1.1k |

- **Skills stay at 9.9k by design.** Claude Code caps the skill listing at
  about 1% of the context window. Before, 327 skill entries competed for that
  budget; after, 205 do, so the skills in use are listed in full instead of
  truncated.
- **Deferred tool names** (`mcp__<server>__<tool>`, listed on every turn in the
  Desktop app) are not in `/context`. From the CLI tool table at 3.2 chars per
  token: 1,436 names ≈ 29k tokens before. Desktop uses 36-character connector
  UUIDs, so its list costs more. Datadog alone is 480 tools (≈10.6k).
- **Desktop app:** not measured fresh (one-host policy; the app cannot start a
  session from a side session). This session's own Desktop context reported
  system prompt 10.9k, system tools 35.8k (app tools), MCP tools 40.8k, memory
  13.8k and skills 9.9k. The Desktop-only cuts below remove about 12 connectors
  (≈3.6k name tokens plus their server instructions), the Shopify plugin server
  and the needs-authentication server list, on top of the CLI savings.
- **Multiplier:** every subagent and `claude -p` dispatch pays the full startup
  context again, uncached. A Duckie session that fans out four subagents paid
  about 5 × 124k before any work.

### What triggered the jump

Checked, with dates:

- The claude.ai Exa, Context7 and Firecrawl connectors were off for Code
  sessions on 2026-10-14 and were back on by 2026-10-26.
- The claude.ai account-plugin buckets under `~/.claude/plugins/synced` were
  regenerated on 2026-10-21 and 2026-10-24 (`~g2` generation). The regenerated
  `adobe-for-creativity` plugin renamed its server to
  `plugin:adobe-for-creativity:Adobe`, so the 2026-10-14 denial stopped
  matching.
- The claude.ai Datadog connector exposes 480 tools.

Not established: whether the switch between two claude.ai organisation buckets
reset the Desktop connector defaults.

### Usage evidence

Window: all transcripts under `~/.claude/projects` with mtime ≤ 30 days. That is
258 files, and in practice only 7 days, because `cleanupPeriodDays` is 7. The
counts are `tool_use` requests, not confirmed successful executions.

- **Used:**
  - Supabase connector: 530 requests (+34 on an older connector id).
  - Slack connector: 370 (+18).
  - Datadog connector: 154 (+51).
  - Claude in Chrome: 418.
  - Gmail: 26.
  - Shared Firecrawl / Context7 / Exa: 32 / 29 / 10.
  - Linear: 10.
  - Sentry: 9.
  - Notion: 2 (+1).
  - Google Drive and Google Calendar: 2 each.
  - Claude Docs: 2.
  - Canva, Microsoft 365, Descript and ElevenLabs: 1 each.
  - RepoWise: 4.
- **Zero requests:**
  - Connectors: Adobe, n8n, Lovable, Upwork, PostHog, SNOMED CT, ICD-10, Twilio,
    Granola, Replit, CourtListener, Indeed, Dice, ZipRecruiter.
  - The claude.ai copies of Exa, Context7 and Firecrawl.
  - Shopify (small-business plugin).
- **Skills invoked:**
  - sarosh-communication 20, media-studio 23, sarosh-audio-voice 6.
  - design:design-critique 5, design:accessibility-review 4, design:ux-copy 2.
  - mobile-* 8, opportunity-engine 3, local-ai-stack 3, portfolio-enrichment 2.
  - No skill from small-business, litigation-legal, marketing, engineering,
    stripe, sentry, slack (official plugin), notion or coderabbit.

## Changes and rollback

Backups of every file changed outside Git are in
`%USERPROFILE%\.claude\backups\usage-diet-2026-10-26\`.

### 1. Plugins disabled (`~/.claude/settings.json` → `enabledPlugins`)

`settings.json` is hand-managed; Sync does not write it (see
`registry/native-connectors.json`, claude host evidence).

| Plugin | Why |
| --- | --- |
| `small-business@inline` | 44 skills, Shopify MCP (40 tools + instructions), 27 unauthenticated servers; unused |
| `litigation-legal@inline` | 19 skills + docket-watcher agent; unused |
| `marketing@inline` | 8 skills, 6 unauthenticated servers; unused |
| `engineering@inline` | 10 skills duplicating code-review/debug; 3 unauthenticated servers |
| `cowork-plugin-management@inline` | Cowork plugin authoring; unused in Code |
| `exa@inline` | duplicate of the keyed shared Exa server (its MCP was already denied) |
| `stripe@claude-plugins-official` | 10 skills, agent, SessionStart "Stripe CLI" tip, unauthenticated MCP; unused |
| `sentry@claude-plugins-official` | 8 skills; unused (the Sentry connector stays) |
| `slack@claude-plugins-official` | 8 skills; MCP already denied; AgentHub `slack` skill owns Slack |
| `coderabbit@claude-plugins-official` | `autofix` and `code-review` are byte-identical to the loose copies |
| `railway@claude-plugins-official` | `use-railway` duplicates the loose copy; MCP already denied; empty hook |
| `linear@claude-plugins-official` | MCP-only and its server was already denied, so it contributed nothing |
| `gitlab@claude-plugins-official` | unauthenticated MCP; GitLab is not used |

Rollback:

- **Marketplace plugin:** run `claude plugin enable <name>@claude-plugins-official`.
- **`@inline` account plugin:** set its `enabledPlugins` value back to `true`.
- **Everything at once:** restore the backup with
  `Copy-Item "$env:USERPROFILE\.claude\backups\usage-diet-2026-10-26\settings.json" "$env:USERPROFILE\.claude\settings.json"`.

### 2. Servers denied (`~/.claude/settings.json` → `deniedMcpServers`)

Added `claude.ai Exa`, `claude.ai Context7`, `claude.ai Firecrawl` (duplicates of
the keyed shared-gateway servers in `~/.claude.json`, restoring the 2026-10-14
decision), `plugin:adobe-for-creativity:Adobe` (renamed duplicate of the Adobe
connector) and `plugin:design:intercom` (unauthenticated, unused).
Rollback: delete the entry from `deniedMcpServers`.

### 3. Desktop connector defaults

Turned off for new Desktop Code sessions through the app's per-session
connector switch, which also sets the default:

- Duplicates: Exa, Context7, Firecrawl.
- Unused: n8n, Lovable, Replit, Twilio, PostHog, Granola, CourtListener,
  SNOMED CT Terminology, ICD-10 Codes.
- Media, off by default later the same day under the orchestrator's authority:
  ElevenLabs (150 tools; paid generation stays on the governed CLI, and
  ElevenLabs is last in the cloud-provider order) and Adobe for creativity
  (113 tools, unused). Both keep their `mediaConnectorRoles`; enable them per
  session when a media step needs them.

The connectors stay connected on the account. Rollback, or one-off use: the
composer's **+ → Connectors** menu in any session. That turns the connector on
for that session and makes it the default again.

### 4. Instruction and memory files

- `C:\Repos\.claude\CLAUDE.md`: the RepoWise-generated block between the
  `REPOWISE` markers (63-repo table, cross-repo contracts and co-changes, tool
  table) was replaced by a short pointer to `list_repos` and
  `get_overview(repo="all")`. That saved about 4k tokens in every session
  under `C:\Repos`. RepoWise has no option to omit these tables. Running
  `repowise generate-claude-md` in workspace mode regenerates them.
  Rollback: copy `Repos.claude.CLAUDE.md` from the backup folder.
- Auto-memory indexes condensed to one short line per memory. Memory files
  were not touched.

  | Project | Before | After |
  | --- | --- | --- |
  | duckie-app | 22.8 KB | 16.6 KB |
  | abacare | 20.8 KB | 19.8 KB |
  | musa-dev-team | 13.9 KB | 12.0 KB |
  | subops | 10.9 KB | 6.6 KB |

  - duckie-app also dropped two superseded index lines whose successors are
    still indexed: `use-sonnet-subagents-for-parallel-work` and
    `release-pr-main-gate`.
  - QA password values were removed from the abacare and subops hooks. They
    remain in the memory files themselves.
  - Rollback: copy `<project>.MEMORY.md` from the backup folder to that
    project's `memory\MEMORY.md`.

## Kept

- **Duckie engineering:**
  - Connectors: Supabase, Slack, Datadog, Linear, Sentry, Gmail, Google
    Calendar, Google Drive, Notion, Claude Docs.
  - Plugins: `supabase`, `notion`, `frontend-design`, `pyright-lsp`,
    `typescript-lsp`.
- **Media:**
  - `media-studio@agenthub`.
  - Connectors Descript and Canva on by default; ElevenLabs and Adobe are
    available per session (all four keep their 2026-10-21 `mediaConnectorRoles`).
  - Account plugins `canva`, `adobe-for-creativity`, `design` (its skills are
    in use).
- **Career:** job-board connectors Indeed, Dice, ZipRecruiter, Upwork.
- **Retained tenant:** Microsoft 365.
- **Shared services:** RepoWise (`repowise@agenthub`), shared Exa, Context7 and
  Firecrawl, Claude in Chrome, the built-in browser, and
  `product-experience-engineering@agenthub`.

## Standing pattern: bulk work goes to API workers, not subagents

Every interactive subagent pays the session's full startup context (about
68–110k tokens here) before it does any work, and that cost comes out of Max
usage. For bulk, self-contained work, prefer a headless API or Batch worker:

- **Use a worker for:** review or QA passes over many files or frames,
  research summaries, transcript and script scoring, and classification or
  extraction over a list of inputs. The work must not need this session's
  tools or conversation.
- **Keep subagents for:** work that needs repository tools, file edits, MCP
  connectors or the conversation's context.
- **How to call it:** call the Anthropic Messages API directly (or the Message
  Batches API for large non-urgent sets). Read `ANTHROPIC_API_KEY` by name and
  never print it. Send only the inputs the task needs, with a small system
  prompt and no host instruction files.
- **Boundaries** (global policy):
  - Owner business work and public or synthetic inputs only. Never send
    Duckie, Pendoah or other client data.
  - Stop on errors, exhausted credit or expiry; do not retry into charges.
  - No extra calls just to verify.
  - The 2026-10-26 credit window and its shared worker are tracked by the
    orchestration ledger, not here.

## Not changed — follow-ups

- **duckie-app `.claude/rules` — done in musa-dev-team/duckie-app#1721.**
  Claude Code scopes a rule file only with `paths:`; the repository's rules
  used Cursor's `globs:`, so all 37 loaded in every session. The PR adds
  `paths:` to 23 rules (mirroring `globs:`, which stays for Cursor) and leaves
  14 short repo-wide rules always-on. Fresh `/context` in a `dev` worktree:
  109.7k → 79.7k tokens (memory files 53.4k → 23.8k). Reading a
  `supabase/migrations/` file loads the six database rules; before any read,
  none are in context.
- **Shared skills directory — done the same day.** `~/.claude/skills` is a
  link to `~/.agents/skills`. That made Claude load loose copies of skills it
  already receives another way:
  - media-studio ×5, product-experience-engineering ×11, use-repowise.
  - Nine Anthropic document skills that claude.ai sync already provides.

  The link stays. `Sync-Capabilities.ps1` now writes `"off"` entries into
  `skillOverrides` in `~/.claude/settings.json`, which is Claude Code's
  documented way to hide a skill without moving it. See
  [context-reduction.md](./context-reduction.md). A fresh `claude -p "/context"`
  showed 205 → 179 skill entries, with loose entries going from 108 to 82. The
  skills listing stayed at 9.9k because of the 1% cap. Entries cut to under 20
  tokens went from 126 to 101.
  Rollback: `claude plugin disable` brings a plugin's loose copies back on the
  next sync. To restore all 26 at once, delete the `skillOverrides` key from
  `~/.claude/settings.json` and clear `hosts.claude.owned` in
  `%LOCALAPPDATA%\AgentHub\sync\skill-overrides.json`. If you only delete the
  key, the next sync writes it again.
- **CLI connector parity.** Desktop connector defaults do not reach the CLI or
  `claude -p` dispatch. Denying the same connectors in `deniedMcpServers` would
  also block re-enabling them for a single session if the Desktop app honours
  that list. Not established either way, so they were left allowed in the CLI.
- **Optional, owner decision:**
  - Datadog (≈10.6k name tokens) stays on globally. Decision 2026-10-26:
    keep it only for Duckie folders if per-project scoping exists. It does not:
    the Desktop connector switch sets one global default, and
    `deniedMcpServers` merges across settings scopes, so a project cannot
    re-allow a server denied at user scope. Non-Duckie sessions can switch it
    off per session from **+ → Connectors**.
- **Local services:** the only MCP started at session start is the RepoWise
  bridge (kept). No Local-AI MCP loads by default, which already matches the
  2026-10-26 cloud-first rule.
  - Raising `cleanupPeriodDays` above 7 would give a longer usage window for
    the next review.
