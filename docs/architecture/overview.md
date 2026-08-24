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
  delivery records.

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

### Known seam gaps

- **Index freshness is not triggered by content change.** OneDrive edits do
  not schedule a Local-AI reindex, so recently authored material is absent
  from retrieval until a build runs. Root `04_Career_and_Public_Profile` is
  the sharpest case: heavily edited, and a rounding error in the index.
- **Ingestion loses most of what it sees.** The last `knowledge` build
  processed 2,858 of 16,382 files; rejections are recorded in the catalog's
  `rejection_events` under a single `unsupported_or_parse_error` category.
  Unparsed content is silently unreachable rather than reported missing.
- **Package-level `references/` do not deploy.** `Sync-AgentHub.ps1` mirrors
  a skill's own directory, so only `skills/<name>/references/` reaches an
  agent host. Skill-relative pointers to package-level references resolve in
  the repo and dangle at runtime; write those as repo-relative paths.
- **Two payload facets carry no signal.** `rag_curation_status` and `scope`
  are uniform across every point in `knowledge_v1`, and `never_name` is
  positive-only — absent means unmarked, never cleared. Do not infer
  nameability from an absent flag.
