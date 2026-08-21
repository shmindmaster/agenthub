---
name: use-knowledge-access
description: Use when asking about client work, methodologies, career evidence, research notes, or anything in D:\OneDrive - MahumTech\Documents\ folders 02 through 06; also for knowledge map, rga/ripgrep-all search, knowledge-access-plan, or grounding an answer in those documents.
---

# Use Knowledge Access (document intelligence)

The documents tree at `D:\OneDrive - MahumTech\Documents\` is the curated
corpus. This skill is the access layer: map, exact search, then read.
RepoWise indexes git repos under `C:\Repos`. Do not point RepoWise at
OneDrive, and do not walk the whole documents tree.

## Authority

1. The file on disk (cite path, and page for PDFs).
2. `AGENTS.md` at the documents root (output rules).
3. `_MAP.md` at the documents root (generated navigation).

When they disagree, trust the file. Never name a client in generated
output unless the user has cleared that client for this turn.

## Roots in scope

```
02_Client_Work
03_Products_and_Startups
04_Career_and_Public_Profile
05_Methodologies_Templates_and_Accelerators
06_Research_and_Knowledge_Base
```

Out of the local sync root (use Microsoft 365 / SharePoint tools, not
this filesystem walk):

- Legacy Credera tenant under the mahumtech-my OneDrive `IP/Clients/Credera/`
- Upwork site `quadtechai.sharepoint.com/sites/Upwork/Shared Documents/`

Folders `00`, `01`, `07` and above are out of scope unless the user
names them.

## Access order

1. Read `D:\OneDrive - MahumTech\Documents\_MAP.md`. Decide the branch.
2. Exact search scoped to that branch:
   `pwsh -NoProfile -File packages/knowledge-access/scripts/Search-Knowledge.ps1 -Query "<literal>" -Root 05`
   (`rga` if installed; otherwise `rg`, which will not see inside PDF/Office).
3. Read only the files that search returned. Never glob or bulk-read a
   directory.
4. Semantic search (local RAG under `D:\rag-index\`) only after 1–3 fail
   to name the target. That index is not built yet — say so rather than
   pretending.

Regenerate the map after a reorganization:

```
pwsh -NoProfile -File packages/knowledge-access/scripts/New-KnowledgeMap.ps1
```

Detect (do not delete) git object stores and regenerable build dirs:

```
pwsh -NoProfile -File packages/knowledge-access/scripts/Find-CodeInKnowledge.ps1
```

Moving or deleting those paths is destructive. Report the table and
stop unless the user has authorized the move.

## Output rules

- Cite the file path (and page, for PDFs) for any factual claim.
- Distinguish what a document states from what you infer.
- Do not name a client unless this turn cleared that name. Describe by
  industry, size, revenue, and constraints instead.
- `03_Products_and_Startups` private ventures (abacare, coledger,
  gentlenext, lawli, lexalign, verigence under Mahumtech / Maya Modest)
  are not Pendoah work. Never describe them as Pendoah clients or
  delivery.

Full plan: `packages/knowledge-access/references/knowledge-access-plan.md`.
Opportunity rendering (resume, bid, proposal, interview): load
`opportunity-engine`.
