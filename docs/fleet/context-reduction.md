# Manual fleet context maintenance

Agent homes are deployment targets. Keep owned instructions and skill changes
in AgentHub sources; never shorten third-party vendor caches in place.

`python scripts/Measure-AgentContext.py --output <private-report.json>` reports
registered global skill roots, instruction sizes, plugin activation metadata
and the explicitly enumerated host config paths. It omits config values and
credentials. Cached skills are not active-tool counts. Repository-local skills
and undocumented host storage require a separate audit.
The storage section also checks the declared app-data locations and immediate
skill/plugin links without scanning their contents. Six whole-library host
junctions resolve to `~/.agents/skills`; they are aliases, not six copies.
Individual skill links and Cursor package links are recorded separately.
Both Python helpers require Python 3.12 or newer for Windows junction checks.

`python scripts/Optimize-AgentContext.py` audits legacy duplicate skill imports.
`--apply` preserves useful unique copies in the shared skill root, copies and
hash-verifies each retired directory into private recovery, then removes only
the allowlisted imported copy. Unknown and conflicting user files are retained.
The recovery manifest records every action. This is manual maintenance, never
a startup or recurring job.

The learning-studio capability stays in the catalog but is opt-in rather than
deployed to every coding host. Native host tools own browser automation;
Claude-specific imported browser instructions must not be presented as usable
on unrelated hosts. Keep useful MCP integrations and original permissions.

Deploy canonical instruction changes with `Sync-Instructions.ps1 -Apply` and
owned skills with `Sync-Capabilities.ps1 -Apply -Prune`. Audit both afterwards.
Pruning only removes unchanged managed copies; a modified copy needs review.

Instruction destinations are surface-specific. Antigravity CLI, Desktop and
IDE share the Gemini-owned `~/.gemini/GEMINI.md`; the instruction audit reports
the concrete owner's state for each shared surface and rejects an invalid owner.
The [current Antigravity rules documentation](https://www.antigravity.google/docs/rules/)
specifies 24,000 bytes per file after inline includes and a 20,000-token aggregate
active-rules budget. File size alone does not establish the aggregate budget.

VS Code's Copilot harness uses
`~/.copilot/instructions/agenthub-global.instructions.md` with `applyTo: "**"`
frontmatter, following its [user instructions documentation](https://code.visualstudio.com/docs/agent-customization/custom-instructions).
Copilot CLI's single `copilot-instructions.md` is a separate discovery route.
Claude and Codex harnesses use their own native sources; existing-session
consumption and profile-specific discovery still need independent verification.

[Cursor rules](https://cursor.com/docs/rules) under `.cursor/rules` are project
rules; a file in the user's home directory does not establish global coverage.
Global User Rules use editor settings. [Cursor Agent](https://cursor.com/docs/cli/using)
documents project rules and project-root `AGENTS.md`/`CLAUDE.md`.
[Warp Global Rules](https://docs.warp.dev/agents/capabilities/rules/) use Warp
Drive; its file rules are project-scoped. These three registry surfaces have
no established global file target and remain explicit deployment gaps.

Cline and OpenCode have separate native tool-discovery plugins in the
coding-agent-dispatch skill. Their manual installers audit by default and use
`-Apply` for hash-verified repair. Each starts with one discovery tool and
loads native tools on demand for the current user turn. Tools and service
credentials stay with the host. This is not a universal adapter for other
agents. Other agents retain their supported native discovery behavior.
Cline MCP synchronization preserves existing deferred-server choices,
approvals and authentication when updating transport settings. Legacy server
names are reconciled through the registry aliases, rather than retaining an
extra npm launcher alongside a native browser integration.

Global plugin files live outside application installations, consistent with
[OpenCode's plugin locations](https://opencode.ai/docs/plugins/). Persistence
of files does not guarantee compatibility with future SDK versions. After an
update, audit the file and run a fresh chat plus a real tool-discovery check.
Record provider input tokens separately from byte counts. A CLI check does
not establish that Desktop rendered or consumed the change.
Keep one measurement row per registry surface, including inactive surfaces.
Label historical receipts separately from fresh before/after measurements.
Mixed-task request usage and cache tokens cannot establish initial-context
savings. When another host cannot be started under the one-host policy, record
the fresh measurement as unknown rather than extrapolating from static bytes.

Usage-based culling needs bounded, named evidence: enumerate log roots and
selection limits, distinguish tool requests from successful execution, and
record activation independently from observed use. No signal in a selected
sample means usage is unknown. Identical hashes or old cache versions alone
do not authorize removing a capability or a vendor cache. Retain unknown-use
entries until the native lifecycle and actual need are established.

Run `python -m unittest discover -s tests -p test_agent_context.py`, the package
Node discovery tests, and the shared PowerShell suite after lifecycle changes.
Keep private policy, rewrite drafts, prompts and recovery copies outside Git.

The fleet audit covers shared deployment and declared configuration metadata;
it does not establish successful inference in every installed application.
Keep separate evidence for CLI execution, Desktop rendering, tool execution,
and each host's supported deployment destinations. Restart existing chats to
measure the new initial context. Future vendor imports may recreate duplicates;
rerun the manual audit after imports or updates rather than adding a watcher.
