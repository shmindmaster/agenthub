# Cross-Agent Memory Seed

Version: 1.1  
Canonical policy: `C:\Repos\agent-capabilities\docs\cross-agent-operating-charter.md`

Load these stable rules in Claude and Codex:

- Classify work as personal capability work, authorized client-project work, or explicitly read-only client research before acting.
- Personal tooling never writes to or uses a client repository, tracker, documentation system, communication system, identity, domain, account, dataset, or deployment as its control plane or test fixture.
- Split mixed personal/client requests before execution.
- Reusable capabilities use synthetic projects and data.
- `C:\Repos\agent-capabilities` is the owner of shared personal capability policy and registry metadata.
- One capability has one owner; one writer owns a file/change set at a time; peers review separately.
- Claude and Codex do not share hidden memory. Shared truth exists only in explicit personal files and supported host instructions.
- Memory stores stable rules and pointers, not client facts or time-sensitive operational state.
- Reverify current facts during the authorized task that needs them.
- Keep proposed, implemented, tested, committed, reviewed, merged, deployed, production-verified, and user/customer-validated gates separate.
- Access failure is a gap, not proof of absence.
- NotebookLM output is derived and nonauthoritative; generic integrations are tested synthetically.
- Never expose or persist credentials, authentication state, customer data, or private source bodies.

This seed supersedes any older memory that implicitly allowed personal agent coordination or reusable tooling to be stored in client systems.

## Fast start for future sessions

1. Read the applicable repository instructions, then this seed; do not reconstruct cross-agent policy from old chats or project reports.
2. Classify the request and state the boundary only when it materially affects execution.
3. For personal capability work, start at `C:\Repos\agent-capabilities`: inspect `registry/capabilities.json`, the canonical capability package, and `state/cross-agent/` for an active handoff.
4. Reuse the existing capability owner and host adapters. Search before creating a new plugin, skill, MCP server, wrapper, or memory file.
5. Do not scan client repositories or invoke client connectors merely to obtain context for personal tooling.
6. Load only task-relevant references; avoid replaying old alignment reports unless the user asks for historical analysis.
7. Before reporting completion, validate the changed capability and state external gates separately.
