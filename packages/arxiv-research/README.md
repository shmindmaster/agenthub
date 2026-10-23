# arXiv research

AgentHub's cross-host product-research workflow uses the unmodified
[blazickjp/arxiv-mcp-server](https://github.com/blazickjp/arxiv-mcp-server)
PyPI release. Upstream owns all paper tools and prompts; AgentHub supplies a
loose skill and a bounded MCP client so the same workflow works across projects
and hosts without a local server per idle host.

Install once with PowerShell 7 and uv:

```powershell
pwsh -NoProfile -File packages/arxiv-research/skills/use-arxiv-research/scripts/Invoke-ArxivResearch.ps1 -Operation install
pwsh -NoProfile -File scripts/Sync-Capabilities.ps1 -Apply -CapabilityId arxiv-research
```

Ask an agent to use `use-arxiv-research` for a product decision. The skill owns
the research-to-experiment workflow and invocation examples. Both the client and
paper server execute only for an explicit invocation. A nonblocking OS file
lock serializes sessions; a second caller fails before starting a server. MCP
SDK 1.x closes and terminates its child process tree on session exit. Windows
launches use CreateNoWindow. Nothing is added to host MCP configs, schedules or
services. Hosts with no local shell can consume a brief produced by a mapped
local host; this is not a claim of cloud execution or active-session reload.

Runtime files stay under the user's local AgentHub runtime. PDF fallback is
installed; semantic `[pro]` extras and their model downloads are omitted. Calls
preserve upstream result/error shapes and exit nonzero for errors or deadlines.

Maintenance is explicit: review upstream changes, update the pinned requirement,
run the client tests and live discovery/read checks, refresh the registry content
hash and deploy the capability. Do not copy upstream code or install a competing
native plugin. No credentials are required for public arXiv research.
