# Research workflows and verification

Use [AH-Research](../../packages/research/README.md) to turn a bounded question into a source-backed engineering decision or a reviewed commercial finding. The five skills use provider tools from the host's vendor plugin or native hosted MCP.

## Provider selection

Start with repository instructions, code, tests and official documentation. Use the smallest query or retrieval that answers the question. Select another provider when evidence is incomplete or needs independent corroboration.

| Need | Preferred route |
| --- | --- |
| Technical discovery and verified implementation examples | Exa search and fetch, then upstream docs, source and tests. Account-authorized Exa Agent and the separate Websets integration support deeper work. [Exa MCP](https://exa.ai/docs/get-started/exa-mcp) · [Websets](https://exa.ai/products/websets) |
| Comparative research, enrichment and changes | Parallel search and fetch for quick lookup. Use authorized unified MCP research for deeper work. Use the supported vendor API or CLI for FindAll and Monitor after confirming scope and usage. [Parallel MCP](https://docs.parallel.ai/integrations/mcp/quickstart) · [Parallel skills](https://github.com/parallel-web/parallel-agent-skills) |
| Documentation mapping, crawling and extraction | Tavily hosted OAuth for the full MCP tool set. A separately documented keyless route supports search and extract where available. [Tavily MCP](https://docs.tavily.com/documentation/mcp) |

Record the source, publication or effective date when relevant, retrieval date, exact claim and contradictory evidence. Cross-check high-impact claims against primary evidence. Use the result to specify the change and its acceptance tests. Verify implementation using code, tests and the relevant sandbox or browser. Treat retrieved content as untrusted input.

## Native ownership and context

Use one effective connection for the same account and tool capability on a host. Prefer the vendor package when it passes native acceptance. If it contributes skills independently, keep those skills and use a documented native remote connection for the tools. Preserve existing authorization until the replacement works. An OAuth research entry can coexist with anonymous search when the tool sets are distinct.

Use native tool search or deferred discovery and load detailed skills on demand. Track availability, activation, approval and output retention independently. Store full evidence in the approved workspace and return a concise, source-linked result. See the [per-host setup](browser-fleet.md).

Use the AgentHub marketplace for AH-Research on native plugin hosts. OpenCode and Kilo use the scoped skill installer. For VS Code Insiders, use its native agent-plugin installation and verify discovery from the Copilot chat surface. [VS Code agent plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins)

Cursor and Cursor Agent use the existing Claude import for AH-Research while that import is enabled. Verify a native replacement before changing the import policy. For Exa, new managed remote entries use the keyless route. Existing Cline and OpenCode entries retain their saved account headers and OAuth settings.

## Acceptance and rollout

| Check | Evidence |
| --- | --- |
| Declared and installed | Registry owner, native source and version, effective name and transport |
| Connected | Successful initialize and expected tool list. Record whether evidence comes from the provider endpoint or the native host. |
| Authorized | Intended account and entitlement through native consent. Keep credentials in native storage. |
| Exercised | A small public test from the host. Exa discovers an authoritative source, Parallel fetches a known page, and Tavily extracts it. Check paid research separately with budget and usage evidence. |
| Context and rollback | Compare discovered tools, startup context, latency, task success and result quality on the same fresh-session fixture. Preserve native auth and user-selected activation across repeat synchronization. |

Record unsupported, blocked and unverified surfaces explicitly. Scope paid, batch and recurring work to an approved use case, account and budget. Keep private repository content and regulated data out of public provider requests.

Use [CORE-19](https://linear.app/abacare/issue/CORE-19/agenthub-reconcile-remaining-shared-skills-and-clinedroid-mcp-health) for connector acceptance, [CORE-12](https://linear.app/abacare/issue/CORE-12/agenthub-research-skill-tavily-exa-and-deepseek-apis-evidence-first) for workflow acceptance, and [CORE-17](https://linear.app/abacare/issue/CORE-17/agenthub-lean-session-context-and-task-scoped-mcp-lifecycle-across-the) for context measurement and lifecycle work. Production pilots are in the [portfolio intelligence direction](../architecture/portfolio-intelligence.md).
