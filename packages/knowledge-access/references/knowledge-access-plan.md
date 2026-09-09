# Knowledge Access Layer

Goal: ask any managed agent about the contents of `01`–`06` and `10` under
`D:\OneDrive - MahumTech\Documents\` and get a grounded answer with
file-level provenance.

RepoWise does not cover this tree. Do not create a git workspace inside
OneDrive.

## Scope

- `01_Business_and_Entities`
- `02_Client_Work`
- `03_Products_and_Startups`
- `04_Career_and_Public_Profile`
- `05_Methodologies_Templates_and_Accelerators`
- `06_Research_and_Knowledge_Base`
- `10_Certifications_Prep`

Also in retrieval scope, not in the local sync root:

- Legacy Credera tenant (`IP/Clients/Credera/` on the mahumtech-my OneDrive)
- Upwork site `quadtechai.sharepoint.com/sites/Upwork/Shared Documents/`

Out of this skill: `00`, `07`–`09`, and `20_Legal_Matters` (Local-AI
alias `legal`).

Clients are never named in generated output unless explicitly cleared —
an output rule, not a retrieval restriction.

## Capabilities (build in order)

| # | Capability | Answers |
| --- | --- | --- |
| 1 | Router — `_INDEX.md` | What exists, where would X be? |
| 2 | Exact search — `rga` / `rg` | Which file mentions this literal? |
| 3 | Read — filesystem tools | What does this file say? |
| 4 | Semantic search — Local-AI Qdrant `knowledge` | Concept I cannot name |

1–3 stay the cheap path (router, literal, read). 4 is the content index:
the existing Local-AI Qdrant service (`policy.single_vector_engine`),
catalog `D:\Local-AI\data\catalog\corpus-v2.sqlite`, collection
`knowledge_v1` via stable alias `knowledge`. One Qdrant, Docker named
volume (host `127.0.0.1:16333`). Do not stand up a second vector engine,
a GPU RAG container, or an NTFS bind-mount. Legal stays on alias `legal`.
Duckie already owns host `6333` — do not steal it.

## Phase 0 — Clean (detect only until authorized)

Nested `.git` and regenerable dirs (`node_modules`, `.venv`, `dist`, …)
inside `01`–`06` and `10` churn OneDrive and pollute search. Detect with
`scripts/Find-CodeInKnowledge.ps1`. Do not move or delete without an
explicit authorization. Repos with no remote are the only copy — move,
never delete. New repos are created under `C:\Repos\<account>\`, never
inside the OneDrive tree.

## Local validation prerequisites

The application-answer profile validator requires the dependencies pinned in
`scripts/requirements.txt`. Provision its local Python 3.13 environment:

```powershell
pwsh -NoProfile -File packages/knowledge-access/scripts/Install-ValidationRuntime.ps1
pwsh -NoProfile -File tests/Test-KnowledgeAccess.ps1
```

The environment lives under `%LOCALAPPDATA%\AgentHub\runtimes\knowledge-access`.
The native test uses that interpreter when present, with `-PythonExecutable`
available for another explicitly provisioned interpreter. Use its
`Scripts\python.exe` for direct calls to `validate_application_answer_profile.py`.
Installation never modifies the host-managed Python or Local-AI retrieval
environment and starts no service. A missing dependency is a failed
prerequisite, not evidence that an invalid profile was correctly rejected.

## Phase 1 — Map

`scripts/New-KnowledgeIndex.ps1` writes `_INDEX.md`, `_maps/<root>.md`,
`_CATALOG.md`, `_ENGAGEMENTS.md`, and a pointer `_MAP.md`. Agents read
`_INDEX.md` first. Regenerate after reorganization.

## Phase 2 — Exact search

`rga` reads PDF/docx/xlsx/pptx. Upstream publishes darwin/linux builds
only — there is no Windows asset and no winget package. On this machine
the script prefers a native `rga`, then `wsl rga`, then `rg` (text only).
`scripts/Search-Knowledge.ps1` wraps that order and requires a scoped root
for literal search (`-Root 01` / `02` / … / `10`).

## Phase 3 — Wire agents

Claude Code / Codex / Grok already have filesystem tools. Claude Desktop
needs a filesystem MCP pointed at the in-scope roots (not persisted
fleet-wide; Desktop-only). Codex can shell out to `rga`/`rg`. Usage rules
live in `D:\OneDrive - MahumTech\Documents\AGENTS.md`.

## Phase 4 — Semantic (Local-AI Qdrant)

Reuse the workstation control plane, not a new product:

```
D:\Local-AI\ai.ps1 start retrieval --gpu-text
D:\Local-AI\ai.ps1 reindex knowledge
D:\Local-AI\ai.ps1 reindex knowledge --activate
```

`--activate` only after source/target count parity. Snapshot before
`--recreate`. Query path for agents:

```
pwsh -NoProfile -File packages/knowledge-access/scripts/Search-Knowledge.ps1 -Query "<concept>" -Semantic
```

That wraps `D:\Local-AI\query.ps1 -Index knowledge`. Agent sees paths,
then reads the real file. Client names in hits stay out of generated
output unless cleared this turn.

Known parser gaps in the catalog (rejected, not embedded): `.doc`,
`.ppt`, `.vsd`, `.xls`, images, audio/video. Folder `10` is mostly
screenshots — text RAG only sees extractable files. Those still need rga
or a parser/OCR upgrade; Qdrant cannot invent text that was never
extracted.

## Workflows on top

Encoded in `opportunity-engine` when a task recurs: case-study matching,
proposal assembly, resume evidence, research synthesis.
