---
name: use-knowledge-access
description: Use when asking about client work, business entities, certifications, methodologies, career evidence, research notes, or anything in D:\OneDrive - MahumTech\Documents\ folders 01–06 or 10; also for knowledge map, rga/ripgrep-all search, knowledge-access-plan, grounding an answer in those documents, or retrieving Qdrant knowledge for resumes, proposals, RFPs, and pitches. Do not use the legal alias. Do not draft those artifacts through a local chat LLM.
---

# Use Knowledge Access (document intelligence)

The documents tree at `D:\OneDrive - MahumTech\Documents\` is the curated
corpus. This skill is the access layer: map, exact search, semantic
search, then read. RepoWise indexes git repos under `C:\Repos`. Do not
point RepoWise at OneDrive, and do not walk the whole documents tree.

## Authority

1. The file on disk (cite path, and page for PDFs).
2. `AGENTS.md` at the documents root (output rules).
3. `_INDEX.md` at the documents root (generated navigation). `_MAP.md`
   is a pointer only.

When they disagree, trust the file. Never name a client in generated
output unless the user has cleared that client for this turn.

## Roots in scope

```
01_Business_and_Entities
02_Client_Work
03_Products_and_Startups
04_Career_and_Public_Profile
05_Methodologies_Templates_and_Accelerators
06_Research_and_Knowledge_Base
10_Certifications_Prep
```

Out of the local sync root (use Microsoft 365 / SharePoint tools, not
this filesystem walk):

- Legacy Credera tenant under the mahumtech-my OneDrive `IP/Clients/Credera/`
- Upwork site `quadtechai.sharepoint.com/sites/Upwork/Shared Documents/`

Folders `00`, `07`–`09` stay out of this skill unless the user names
them. `20_Legal_Matters` is Local-AI alias `legal`, never this skill.

Semantic index: Local-AI Qdrant alias `knowledge` (catalog
`D:\Local-AI\data\catalog\corpus-v2.sqlite`, collection `knowledge_v1`).
One Qdrant, Docker named volume, host port from `registry.json`
(currently `127.0.0.1:16333`). Do not create a second vector store, do
not bind-mount Qdrant onto `D:\Local-AI\data\qdrant`, do not query
Duckie's Qdrant on `6333`.

## Access order

Forbidden: `Get-ChildItem -Recurse` on the Documents root, reading a
full-tree map, and the Portfolio Audit skill (that skill is for git
repos under `C:\Repos`). Those are why agents time out here.

1. Read `D:\OneDrive - MahumTech\Documents\_INDEX.md` (router, short).
2. Open **one** of `_CATALOG.md`, `_ENGAGEMENTS.md`, or `_maps/<root>.md`.
3. Filename search: `Search-Knowledge.ps1 -Query architecture -Root 02 -NamesOnly`
4. Content search scoped to that branch:
   `Search-Knowledge.ps1 -Query "<literal>" -Root 05`
   `-Root` accepts `01`–`06`, `10`, a folder name, or a deeper path.
5. Semantic (meaning, not a filename):
   `Search-Knowledge.ps1 -Query "<concept>" -Semantic`
   Optional `-Root 01` (or 02–06, 10) filters hits to that tree. This
   calls Local-AI Qdrant `knowledge` via `D:\Local-AI\query.ps1`. Do not
   query the `legal` alias from this skill.
6. Read only the files returned. The index is a pointer; the file on disk
   is still authority.
7. Resume/application claims must pass
   `04_Career_and_Public_Profile/FINAL_CAREER_BRAND_PACKAGE/18_Claim_Matrix_Public_Safe.md`
   before they leave this tree.

Regenerate the router after a reorganization:

```
pwsh -NoProfile -File packages/knowledge-access/scripts/New-KnowledgeIndex.ps1
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
