# Cross-Agent Operating Charter

Version: 1.0  
Owner: `C:\Repos\shmindmaster\agenthub`  
Applies to: Claude, Codex, and other personal agent hosts

This charter is the durable personal control plane for cross-agent work. It governs how agents coordinate; it is not a source of truth for any client project.

## 1. Classify the task before acting

Every substantive task must be classified as exactly one of:

- **Personal capability work:** reusable plugins, skills, MCP servers, agent coordination, portfolio infrastructure, or experiments owned personally.
- **Authorized client-project work:** work explicitly requested for a named client project and limited to the systems and mutations authorized in that request.
- **Read-only client research:** an explicitly requested evidence review with no client-system or client-repository mutations.

If a request mixes personal infrastructure with client work, split it into separate workstreams before acting. Personal capability work must not be stored, tracked, tested, or deployed in client systems.

## 2. Client boundary

For personal capability work, agents must not:

- create issues, pages, channels, messages, branches, pull requests, deployments, accounts, notebooks, or configuration in a client system;
- add personal coordination files, agent instructions, generated reports, private folders, or plugin configuration to a client repository or workspace;
- use client identities, mailboxes, domains, credentials, datasets, source bodies, or production environments as development fixtures;
- make a reusable capability depend on access to a client connector or client approval process;
- treat a client's work tracker as the authority for personal agent allocation.

An action is not permitted merely because it is reversible, read-only, or technically accessible. It must also belong to the classified task.

Client systems may be accessed only during a separately authorized client task. The authorization must identify the client scope and does not carry into later personal tooling work.

## 3. Synthetic-first development

Reusable capabilities are developed and validated with synthetic projects, notebooks, users, documents, identifiers, endpoints, and media. Examples must use neutral names and non-routable or localhost endpoints.

Credentials, cookies, OAuth state, browser profiles, master tokens, bearer tokens, private evidence, and customer data remain outside repositories and agent memory.

## 4. Shared context and memory

Claude and Codex do not share hidden model memory. They share only explicitly maintained personal files and supported host instruction mechanisms.

The stable cross-agent memory seed is `docs/cross-agent-memory-seed.md`. It contains policies and pointers only—not client facts, current ticket states, stakeholder claims, source bodies, or operational snapshots.

Agents must reverify time-sensitive facts in the authorized source during the task that needs them. Prior agent reports and memory are leads, never current proof.

## 5. Ownership and coordination

- Each reusable capability has one canonical owner recorded in `registry/capabilities.json`.
- One agent owns each writable file or bounded change set at a time.
- The author writes the implementation; the peer writes a separate review.
- Silence, a missing review, or an agent's agreement with itself is not approval.
- Personal task claims and handoffs belong under `state/cross-agent/`, never in a client tracker.
- Before writing, inspect current files, repository state, and active work. Preserve unexplained work.

## 6. Evidence and status language

Keep these gates distinct:

1. Proposed
2. Implemented locally
3. Tested
4. Committed
5. Reviewed
6. Merged
7. Deployed
8. Production-verified
9. User- or customer-validated

Never use “complete” without naming the gate met. Connector failure is an access gap, not evidence that no record exists.

## 7. Peer review and consolidation

Independent review means refreshing the relevant evidence without copying the author's conclusion first. The peer records verified claims, rejected claims, remaining conflicts, and required human decisions.

Only the nominated maintainer consolidates shared personal documents. Strategic, legal, commercial, financial, production, or cross-boundary decisions require explicit user approval.

## 8. Derived systems

NotebookLM and similar systems produce derivative research and media. Their output is never authoritative evidence. Reusable integrations must be project-neutral and tested synthetically. Project-specific ingestion requires a separately authorized project task and an approved source manifest.

Shwiki remains a read-only evidence/provenance capability. Derived output must not be written directly into its generated artifacts. Any retained report must first become reviewed, source-grounded material in an authorized personal or project repository.

## 9. Incident correction

When an agent crosses a boundary:

1. Stop new mutations.
2. Identify exactly what changed.
3. Remove or reverse only the agent-owned changes.
4. Preserve unrelated and pre-existing work.
5. Verify cleanup without expanding access.
6. Record the stable lesson in this personal charter or memory seed, not in the affected client system.

## 10. Start and finish checklist

Before work:

- classify the task;
- read applicable repository instructions and this charter;
- confirm the canonical capability owner;
- inspect current work and coordination records;
- identify permitted systems and forbidden boundaries.

At handoff:

- list changed files and external mutations;
- report validation by gate;
- identify access gaps and unresolved decisions;
- state whether any client system was accessed or changed;
- leave a personal session delta when another agent must continue.

