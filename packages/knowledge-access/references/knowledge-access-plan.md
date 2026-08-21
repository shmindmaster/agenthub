# Knowledge Access Layer

Goal: ask any managed agent about the contents of `02` through `06` under
`D:\OneDrive - MahumTech\Documents\` and get a grounded answer with
file-level provenance.

RepoWise does not cover this tree. Do not create a git workspace inside
OneDrive.

## Scope

- `02_Client_Work`
- `03_Products_and_Startups`
- `04_Career_and_Public_Profile`
- `05_Methodologies_Templates_and_Accelerators`
- `06_Research_and_Knowledge_Base`

Also in retrieval scope, not in the local sync root:

- Legacy Credera tenant (`IP/Clients/Credera/` on the mahumtech-my OneDrive)
- Upwork site `quadtechai.sharepoint.com/sites/Upwork/Shared Documents/`

Clients are never named in generated output unless explicitly cleared —
an output rule, not a retrieval restriction.

## Capabilities (build in order)

| # | Capability | Answers |
| --- | --- | --- |
| 1 | Map — `_MAP.md` | What exists, where would X be? |
| 2 | Exact search — `rga` / `rg` | Which file mentions this literal? |
| 3 | Read — filesystem tools | What does this file say? |
| 4 | Semantic search — local index at `D:\rag-index\` | Concept I cannot name |

1–3 are the working system. 4 is optional and local-models-only.

## Phase 0 — Clean (detect only until authorized)

Nested `.git` and regenerable dirs (`node_modules`, `.venv`, `dist`, …)
inside `02`–`06` churn OneDrive and pollute search. Detect with
`scripts/Find-CodeInKnowledge.ps1`. Do not move or delete without an
explicit authorization. Repos with no remote are the only copy — move,
never delete. New repos are created under `C:\Repos\<account>\`, never
inside the OneDrive tree.

## Phase 1 — Map

`scripts/New-KnowledgeMap.ps1` writes `_MAP.md`. Agents read it first.
Regenerate after reorganization.

## Phase 2 — Exact search

`rga` reads PDF/docx/xlsx/pptx. Upstream publishes darwin/linux builds
only — there is no Windows asset and no winget package. On this machine
the script prefers a native `rga`, then `wsl rga`, then `rg` (text only).
`scripts/Search-Knowledge.ps1` wraps that order and requires a scoped root.

## Phase 3 — Wire agents

Claude Code / Codex / Grok already have filesystem tools. Claude Desktop
needs a filesystem MCP pointed at the five roots (not persisted fleet-wide;
Desktop-only). Codex can shell out to `rga`/`rg`. Usage rules live in
`D:\OneDrive - MahumTech\Documents\AGENTS.md`.

## Phase 4 — Semantic (not started)

Only after 1–3 demonstrably fail. RAGFlow + BGE-M3 + local Qwen, index
outside OneDrive at `D:\rag-index\`. One collection per top-level folder.
Agent sees paths, then reads the real file.

## Workflows on top

Encoded in `opportunity-engine` when a task recurs: case-study matching,
proposal assembly, resume evidence, research synthesis.
