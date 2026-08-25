# Architecture Overview

## The registry model

`registry/*.json` is the parity contract between canonical package content
and per-host deployment:

- `agents.json` — host-native config paths, surfaces, instruction files.
- `capabilities.json` — capability ownership, canonical sources, content
  hashes (over git-tracked files), per-host deployment status.
- `mcps.json` — shared MCP servers with environment/OAuth credential
  references (never values), protocol-revision evidence, activation policy.
- `fleet-profile.json` — dispatch policy, autonomy profiles, host surfaces.
- `repo-standard.json` — fleet repository roster + standard rule parameters
  for the checker.
- `mobile-scope.json` — which products may receive native mobile work, and
  which have their mobile identity frozen pending repositioning. Absence from
  it never means eligible; `tests/Test-MobileScope.ps1` fails on any
  unclassified fleet repository.
- `plugin-formats.json`, `subagent-formats.json`, `native-connectors.json`,
  `gateway-profiles.json`, `product-video-delivery.json` — host format and
  delivery records. `native-connectors.json` -> `thirdPartyExtensions` is
  the inventory of official plugins and skills AgentHub does not own
  (Superpowers, Firecrawl, Clerk, Railway, Framer, Remotion, and similar).
  Those install from each host's official channel. AgentHub marketplace
  entries are only for capabilities this repo authors.

## Flow

```text
packages/<capability>  ──hash──▶  registry/capabilities.json
        │                                │
        ▼                                ▼
Sync-Capabilities.ps1            Sync-AgentHub.ps1
(loose skills to hosts)          (instructions + MCP config to hosts)
        │                                │
        └────── Validate-AgentHub.ps1 + tests/ keep both honest ──┘
```

- `scripts/AgentHub.ps1` is the lifecycle entry point
  (inventory / validate / sync / drift).
- `scripts/Check-RepoStandard.ps1` sweeps every fleet repo for the knowledge
  standard; `registry/repo-standard.json` is its roster.
- Content hashes are recomputed with `scripts/RegistryContentHash.ps1`
  whenever package content changes.

## RepoWise workspace

One workspace at `C:\Repos` indexes git repos under `shmindmaster`,
`sh-pendoah`, `musa-dev-team`, and `pendoah`; the `repowise-workspace` MCP
entry (stdio, on-demand-local, `repowise mcp C:/Repos`) is the single agent
surface. Workspace YAML lives at `C:\Repos` (unversioned container); the
versioned declaration of the arrangement is this file plus
`registry/mcps.json` and `registry/repo-standard.json`. Per-repo indexes
are stored in each repo's `.repowise/` directory.

## Knowledge-access documents layer

`packages/knowledge-access` is the sibling for curated documents under
`D:\OneDrive - MahumTech\Documents\` folders `01`–`06` and `10`. It is
not a RepoWise workspace: OneDrive is not a git root, and client names
are an output gate. Agents read `_INDEX.md`, then exact-search or
Local-AI Qdrant `knowledge`, then specific files. Runtime engagement
records stay in the private `C:\Repos\shmindmaster\portfolio-records`
repository.

### Three roots, one contract

```text
D:\OneDrive - MahumTech\Documents   content, authoritative, never versioned here
              │  indexed by
              ▼
D:\Local-AI                          runtime: Qdrant, embeddings/rerank, catalog
              │  discovered via registry.json
              ▼
C:\Repos                             code, config and policy that operate on both
```

- **OneDrive holds content.** It is the authority for any factual claim.
  No code, no config, no derived index.
- **Local-AI holds derived state.** Qdrant collections, the corpus catalog
  and inference services are all rebuildable from OneDrive. Nothing is
  authored here, and it is not a git project.
- **C:\Repos holds logic.** Skills, scripts, schemas and config. It reaches
  Local-AI through `D:\Local-AI\registry.json` (service endpoints and the
  Python runtime), never by hard-coded ports or paths, and reaches OneDrive
  only through the index or an explicit scoped search.

Direction is one-way: content → index → logic. A script that writes content
into OneDrive, or an index treated as authority over the file on disk, is a
break in the contract.

`packages/knowledge-access` owns both directions of this seam:
`scripts/Search-Knowledge.ps1` for locating documents and
`scripts/Get-EvidenceAugmentation.ps1` for retrieving layered material to
augment a document being written. Layer and rendering-mode definitions are
data in `config/evidence-layers.json`, not code.

### Which store answers which question

Three stores, three different retrieval models. Picking wrong wastes a search
and, worse, returns a confident empty result.

| You are asking | Store | Surface |
| --- | --- | --- |
| What have we done, built, proposed, or written about X | Qdrant `knowledge` | `Search-Knowledge.ps1 -Semantic`, `D:\Local-AI\query.ps1 --index knowledge` |
| Anything touching a legal matter | Qdrant `legal` | `query.ps1 --index legal` only |
| Where is this symbol, who wrote it, what breaks if I change it | RepoWise | `repowise-workspace` MCP, `repo=<alias>` or `repo=all` |
| What does this repo's code actually do | the repo | read the file; RepoWise navigates, it does not adjudicate |

The dividing line is **how you know what you are looking for**:

- **You know the meaning but not the words** -> Qdrant. It is a vector index;
  "identity governance assessment" finds a document that never uses that
  phrase.
- **You know the word, or you need structure** -> RepoWise. It is FTS5 keyword
  matching plus a symbol/call graph. `wiki_symbols`, `graph_edges` and
  `git_function_blame` answer questions no vector index can, and it will miss
  a concept that does not share vocabulary with your query.

**RepoWise stores no embeddings.** There is no semantic search over code today.
A question phrased in different words than the source uses will come back
empty, and that empty result is not evidence the code lacks the thing. Reach
for `grep` on a synonym before concluding absence.

Do not consolidate these. `legal` is walled off from `knowledge` at the
collection level so opportunity and resume work physically cannot reach legal
matters; a payload filter would make that boundary a forgettable argument.
RepoWise stays SQLite because a graph traversal is not a vector query.

### Known seam gaps

- **Index freshness is not triggered by content change.** OneDrive edits do
  not schedule a Local-AI reindex, so recently authored material is absent
  from retrieval until a build runs. Root `04_Career_and_Public_Profile` is
  the sharpest case: heavily edited, and a rounding error in the index.
- **The three indexing stages are separate commands.** `ai.ps1 reindex` only
  syncs catalog to Qdrant. Picking up new or changed files needs
  `corpus_v2.py scan` then `corpus_v2.py build` first. A reindex run alone
  reports `complete: true` against whatever the catalog already held, which
  reads as success and is not.
- **Fixed 2026-08-24: the catalog was split in two.** `corpus_v2.py` wrote to
  `shared\catalogs\corpus-v2.sqlite` while `reindex.py` read
  `indexes[].source_database` from `registry.json`, which points at
  `data\catalog\corpus-v2.sqlite`. Build and reindex operated on different
  databases, so a build could succeed and change nothing retrievable, and the
  reindex would honestly report zero work because everything it could see was
  already synced. `corpus_v2.py` now resolves its catalog from the registry.
  Anything writing to this pipeline must take its path from `registry.json`,
  never a hard-coded default.
- **Fixed 2026-08-24: legacy Office formats now parse.** Pre-2007 binary
  Office (`.doc`, `.xls`, `.ppt`) is read by `office_oxide`, and macro-enabled
  OOXML (`.docm`, `.xlsm`, `.pptm`) routes to the existing stdlib OpenXML
  parser by extension alias. A file whose extension claims OOXML but whose
  bytes are OLE2 is re-read as its legacy equivalent rather than rejected.
  Catalog went 16,110 -> 19,190 canonical documents and 414,492 -> 457,150
  chunks; `02_Client_Work` gained 1,635 documents and `05_Methodologies`
  1,173. Rejections now carry one of seven disjoint categories instead of a
  single `unsupported_or_parse_error` bucket, so a missing converter is
  distinguishable from a real parse failure without reading `message`.
  Two residual classes are genuinely unreadable, not deferred: 61 of 222
  `.xlsm` are ECMA-376 AES-encrypted and need a password nobody has, and 937
  `.vsd`/`.mpp` (0.61 GB) have no reader on any platform here -- Visio and
  Project are not installed, so conversion is equally impossible on this
  machine.
- **The index is wider than the skill that reads it.** `knowledge` scope in
  `corpus-v2.sqlite` registers roots `00`, `07`, `08` and `09` next to the
  `01`-`06`/`10` that `use-knowledge-access` declares in scope, so personal
  finance, family records and inbox capture sit in the same collection as
  client work. Nothing at the collection level separates them. Retrieval
  profile is the only boundary, which is why `-Profile client-facing` is
  mandatory for anything leaving the machine.
- **Package-level `references/` do not deploy.** `Sync-AgentHub.ps1` mirrors
  a skill's own directory, so only `skills/<name>/references/` reaches an
  agent host. Skill-relative pointers to package-level references resolve in
  the repo and dangle at runtime; write those as repo-relative paths.
- **Two payload facets carry no signal.** `rag_curation_status` and `scope`
  are uniform across every point in `knowledge_v1`, and `never_name` is
  positive-only — absent means unmarked, never cleared. Do not infer
  nameability from an absent flag.
