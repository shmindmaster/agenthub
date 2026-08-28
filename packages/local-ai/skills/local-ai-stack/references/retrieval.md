# Local-AI retrieval and routing (progressive load)

Load when the task needs RAG/Qdrant, chat model policy, or knowledge/legal scope.
Control plane remains `ai.ps1` / `$LocalAiControl`.

## Route matrix

Read endpoint URLs and model IDs from `$LocalAiRegistry`; do not invent them,
pull ad-hoc models, or copy weights outside `policy.single_model_root`.

### 1) Model routes

- **Chat and assistant APIs**: Open WebUI calling the declared Local-AI API
  (`:8787/v1`), which generates through llama.cpp (`provider.local`).
- **Local inference provider layer**: the declared llama.cpp service. Ollama
  remains an Open WebUI connection with empty tags; do not pull models into it.
- **Model contract source**: `$LocalAiRegistry` under `capabilities`.

### 2) RAG routes

- **Primary retrieval API**: the declared Jina embeddings, rerank, and
  multimodal service.
- **Vector store**: the single declared Qdrant service.
- **Persistent indexing contract**: the catalog at
  `data\catalog\corpus-v2.sqlite` under the resolved root feeds versioned
  Qdrant collections exposed through the stable aliases `knowledge` and
  `legal`. Resolve the alias to find the current collection; never hard-code
  a `_vN` name, because the version rotates on every rebuild. Older personal/legal SQLite
  databases are migration inputs only, not retrieval engines.
- **Index metadata contract**: `indexes` in `$LocalAiRegistry`.

#### Store inventory — the whole set

Two Qdrant collections behind the two stable aliases, one catalog, and two
small runtime databases owned by the legal discovery app. Nothing else in this
stack is a corpus. Resolve every path from `$LocalAiRegistry`; the entries
below name what exists, not where to hard-code it.

There is **exactly one** `corpus-v2.sqlite`, because `corpus_v2.py` resolves it
per index from `indexes[].source_database`. A second copy anywhere in the tree
is not a spare — it is a database something can be pointed at that no refresh
ever updates, so a build reads a stale catalog and reports success against it.
One such orphan was found on 2026-08-24, 113k chunks behind the live catalog
and still named as canonical by validation constants that had stopped tracking
reality. `nightly-refresh.ps1` now warns when it finds one.

**This stack's Qdrant publishes on 16333.** Port 6333 is the default a
different local Qdrant (client work) binds. A URL or fallback pointing at 6333
does not fail loudly — it queries someone else's vector store, or nothing.
Several fallbacks in `apps\api\engine` still said 6333 as of 2026-08-25.

#### 2a) Direct corpus query (read-only helper)

`query.py` at the stack root (with the `query.ps1` wrapper) is the direct,
read-only path to the corpus: it resolves the declared retrieval model and the
`knowledge` or `legal` stable alias from `$LocalAiRegistry`, embeds the query
locally with the declared model, and searches Qdrant directly — no retrieval
API layer required:

```powershell
& (Join-Path $LocalAiRoot 'query.ps1') --index knowledge --limit 5 --threshold 0.5 'your question'
```

It reads only; it never writes, indexes, or controls the stack. Keep write and
index operations on `$LocalAiControl`. It is a convenience around the same
collection/alias contract as the retrieval API, not a second source of truth.

For resumes, proposals, RFPs, and pitches, agents retrieve `knowledge` as
evidence (`use-knowledge-access` / `opportunity-engine`). They do **not**
draft those artifacts by calling a local chat LLM.

#### 2b) Keeping a corpus current

One control-plane verb does the whole cycle. Prefer it over calling the stages
by hand, and over invoking the script under `indexing\` directly:

```powershell
& $LocalAiControl refresh knowledge   # or legal, or all
```

Scope names come from `registry.json` -> `indexes[].id`; `refresh` rejects
anything else and lists what is valid. `all` stops at the first failing scope.
The verb runs `indexing\update-corpus.ps1`, which is where the flags below live
and which can still be called directly when you need one of them.

It runs scan, build, checks whether a rebuild is actually due, rebuilds
blue/green into the next collection version, verifies point parity against the
catalog, switches the stable alias, and deletes the collection the alias used
to serve. It exits early and embeds nothing when live points already equal
catalog chunks. `-NoActivate` builds without cutting over; `-KeepPrevious`
keeps the old collection; `-ActivateOnly` cuts over to whatever
`target_collection` already names, without scanning, building, or embedding.

Use `-ActivateOnly` to finish a build that landed outside this script -- a
`resume-reindex.ps1` run that completed on its own, or an earlier
`-NoActivate`. Without it, `-NoActivate` was a one-way door: the only route to
the alias was rebuilding from scratch. The parity gate still applies, so a
short collection leaves the alias alone.

Cut over in two steps when the delete is the risky part:
`-ActivateOnly -KeepPrevious`, query the alias and confirm the results are
sane, then delete the old collection. Point parity says the right number of
vectors arrived; it says nothing about whether they retrieve.

The embed step is delegated to `resume-reindex.ps1`, which supplies retry
across a service restart, vector reuse, and a CUDA assertion. Call that script
directly only to finish a run that already has a checkpoint; for anything
starting from files on disk, `update-corpus.ps1` is the entry point.

`-Scope` accepts whatever `registry.json` -> `indexes[].id` defines, resolved at
runtime by `reindex.all_scopes()`; the list is not spelled out in code. Adding
or removing a registry index is therefore sufficient, and a registry index that
`reindex.py` refuses by name is a bug, not a boundary. Today that is
`knowledge` and `legal`.

**There is deliberately no `code` index.** One was registered on 2026-08-24 and
removed the same day after it was priced: 4,240 MB of source across the four
`C:\Repos` roots divides by the measured average chunk (1,847 chars) into
roughly 0.8-2.4 million chunks, or 12-51 hours of continuous GPU embedding --
two to six times the entire knowledge corpus, for content that is substantially
lockfiles, generated code, and config. RepoWise already indexes those same
repos with FTS5 plus a symbol and call graph. Route code questions there. If a
code corpus is ever revisited, scope it to hand-picked source paths and price
it against a measured chunk size first; do not point it at a repo root.

Steady state is **one collection per corpus**. The `_vN` suffix is not an
archive — it exists so a rebuild has somewhere to land while the current
collection keeps serving, and the previous version is retired after parity
passes.

Scheduled task `LocalAI-CorpusRefresh` runs `indexing\nightly-refresh.ps1`
daily at 02:00, which calls `update-corpus.ps1` once per registry scope and
transcribes everything to `shared\logs\nightly-refresh.log`. A run that finds
nothing new exits without embedding — measured 2026-08-24 at 18 seconds for
both corpora. It registers with `-LogonType Interactive`, so it runs only while
the account is logged on; making it logon-independent needs `S4U`, which
requires an elevated shell to register.

Four properties of this pipeline are easy to get wrong:

- **Three separate stages, and `reindex` is only the third.** `ai.ps1 reindex`
  syncs catalog to Qdrant and nothing else: it never notices a new or edited
  file and never moves an alias, so run alone it reports `complete: true`
  against whatever the catalog already held. New or changed files need
  `corpus_v2.py scan` then `corpus_v2.py build` first. `ai.ps1 refresh` is the
  verb that does all three plus the cutover; reach for `reindex` only when you
  specifically want that one step.
- **Any content change forces a full rebuild -- but a rebuild is cheap now.**
  `reindex.py` derives a source manifest by hashing every chunk payload in the
  scope, so adding a single document invalidates the checkpoint. Checkpoint
  resume covers interrupted runs, not corpus growth, which is why the update
  path is blue/green. What used to make that expensive was re-embedding every
  unchanged chunk along with the new ones. `--reuse-from <collection>` copies
  the stored vector instead whenever the chunk ID matches. This is exact, not
  approximate: `corpus_v2` builds `chunk_id` as
  `_stable_id("chunk", document_id, ordinal, chunk_ordinal, chunk_hash)`, so a
  matching ID is the same text, and any edit changes the hash and the ID.
  Measured 2026-08-24 on `knowledge`: 344,273 of 386,931 chunks reusable
  (89%), 42,658 (11%) genuinely new. Reuse does not make embedding faster --
  it removes work. Copying runs at 100-350 points/s; the remaining 11% still
  embeds at its normal 12-19 points/s. End to end that is ~20 min of copying
  plus ~50 min of embedding against 4.9 h, so budget roughly a 4x saving, not
  the 18x the copy-phase rate alone suggests. Read a rate sampled during the
  copy phase as the copy phase only.
  `resume-reindex.ps1` resolves the reuse source from whatever the stable
  alias currently serves, so you do not pass it by hand; `-NoReuse` forces a
  full re-embed if you ever need to rebuild vectors from scratch (an embedding
  model change is the case that requires it -- reuse is only valid while the
  model fingerprint is unchanged).
- **`--recreate` refuses a live collection.** It will not touch a collection a
  stable alias points at, and will not accept an alias name as a target. Build
  the next version, verify, then move the alias.
- **Failure signals are unreliable.** `ai.ps1 reindex` exits `0` while
  reporting a fatal error, and a checkpoint's `source_total` is written by the
  job itself, so a supervisor that trusts it reports completion while work is
  pending. Verify against `reindex.source_count()` and the live point count,
  not against either exit code or the checkpoint. `resume-reindex.ps1` does
  this at the end of every run and exits non-zero on a short count.
- **A PowerShell supervisor must not run under `$ErrorActionPreference =
  'Stop'` while merging a child's streams with `*>&1`.** That combination
  promotes any native-command stderr into a terminating `NativeCommandError`.
  Since `reindex.py` reports failure as a JSON line on stderr, the exact event
  a retry loop exists to handle throws straight past the loop and kills the
  supervisor. Observed 2026-08-24: a knowledge rebuild aborted on attempt 1 at
  271,136 / 386,931. Set `Continue` around the child call and judge it by
  `$LASTEXITCODE`.

- **Never write `registry.json` with `Set-Content -Encoding UTF8`.** Under
  `pwsh` 7 that is BOM-free; under Windows PowerShell 5.1 it prepends a UTF-8
  BOM, and `corpus_v2.py`, `reindex.py`, and `query.py` read the registry with
  `encoding="utf-8-sig"` only because of this. Strict `utf-8` raises on a BOM.
  Use `[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))`,
  which behaves identically on both editions. This matters most where nobody
  looks: an interactive operator runs `pwsh`, while a scheduled task runs
  `powershell.exe`, so the corruption appears only under the scheduler.
  Observed 2026-08-24 -- `update-corpus.ps1` succeeded by hand for hours, then
  broke the corpus pipeline on the nightly task's first execution.
- **`@Args` on a `$null` splats one `$null`, not nothing.** A dispatcher that
  collects trailing flags with `[Parameter(ValueFromRemainingArguments)]` gets
  `$null` when the verb ends the line, and splatting that passes a single null
  which binds to the first positional slot the callee still has free. On
  2026-08-25 `ai.ps1 refresh knowledge` therefore reached `update-corpus.ps1`
  as `-BatchSize 0`, and `reindex.py` rejected every attempt before embedding
  a chunk. Normalize once in the dispatcher
  (`$Arguments = @($Arguments | Where-Object { $null -ne $_ })`) rather than at
  each call site — there were twenty, and missing one reintroduces it
  elsewhere. This class of bug hides in the path you never exercise: a refresh
  that finds nothing new never reaches the embed, so the pipeline looks healthy
  for exactly as long as the corpus is already current. Exercise the *working*
  path too, by planting a change and letting the job do real work.
- **Log the argument vector before invoking a child.** argparse names the flag
  it rejected but never the value it received, so a failing log otherwise
  cannot tell you which caller supplied what.
- **Only one corpus refresh may run at a time.** `refresh` holds a lock
  (`shared\state\corpus-refresh.lock`, opened `FileShare::None`) for the whole
  run and fails fast if another holds it. A rebuild picks its target as
  `$live + 1`, records it in the registry, then switches the alias and deletes
  what it replaced; two concurrent runs choose the same `_vN`, overwrite each
  other's `target_collection`, and the loser deletes the collection the winner
  just activated — leaving the alias resolving to nothing. A scheduled task's
  "do not start a new instance" policy does not cover this: it constrains that
  task against itself, not an operator starting a refresh by hand while the
  nightly one is mid-rebuild. Prefer a held handle to a lock *file*, so an
  abnormally terminated run releases it when the OS closes the handle.
- **Test a scheduled job by starting the task, not by running its script.**
  The script passing in your shell says nothing about the edition, working
  directory, environment, or logon context the scheduler will give it.
- **Confirm which collection a query actually hit.** `query.py` prints
  `[collection] <name>`; read it. Blue/green only protects readers if the
  query path follows the stable alias, and until 2026-08-24 it did not:
  `resolve_collection` read `["result"]["name"]` from
  `GET /collections/<alias>`, that response has no `name` field, the `KeyError`
  was swallowed by a bare `except Exception: pass`, and every query fell
  through to `target_collection`. During a rebuild that is the half-built
  collection. It now reads `GET /aliases` instead. The general lesson: an alias
  that is correct in Qdrant proves nothing about which collection the reader
  resolves to -- check the reader, not the alias.
- **A restart silently downgrades the embedder to CPU.** In
  `apps/retrieval/service.py`, `JINA_TEXT_DEVICE` defaults to `cpu` while the
  reranker and omni models default to `cuda` when it is available. CUDA for
  text only happens when `ai.ps1 start retrieval --gpu-text` is passed, so any
  restart brings the service back on CPU with no error and no warning -- a
  multi-hour embed job then runs roughly 20x slower and still looks healthy.
  Check `devices.text` on `:8790/health` before and during a long run.
- **The retry budget is far shorter than the outage it must survive.**
  `reindex.py` retries a failed request 3 times with 1/2/4s backoff: about
  seven seconds. A `docker compose` bounce of the stack takes 30-55s, so the
  job exhausts its retries inside the outage, writes a checkpoint, and exits
  0. Observed 2026-08-24 at 38,816 of 386,931 chunks. Do not run a full
  rebuild unsupervised:

```powershell
pwsh -File (Join-Path $LocalAiRoot 'indexing\resume-reindex.ps1') -Scope knowledge
```

  It relaunches from the checkpoint until the catalog is fully embedded,
  asserts `devices.text` is `cuda` before every attempt, and judges failure by
  "embedded nothing" rather than by exit code. It never passes `--recreate`:
  the checkpoint is the only reason a restart is cheap, and recreating would
  discard everything already embedded.

Both build and reindex must resolve the catalog from `$LocalAiRegistry`
(`indexes[].source_database`). A hard-coded catalog path silently splits the
pipeline: the build writes one database and the reindex reads another, and the
reindex then honestly reports zero work.

### 3) Media routes

- **Image**: Visual Bank + `ai.ps1 image` (single/batch/post/mask/design/enroll/…);
  see Image — FROZEN Visual Bank section above.
- **Voice and TTS/STT**: Qwen3-TTS via `faster-qwen3-tts` only (`voice.clone` /
  `voice.role` / `voice.design`) plus STT; see Voice TTS section above. Kokoro
  / `audio.tts.bulk` removed.
- **Video (motif)**: `ai.ps1 motif` (ComfyUI).
- **Music beds**: `ai.ps1 music` — ACE-Step resident, **not** ComfyUI. See `references/music.md`. TTS does not need this route.

Resolve which media capabilities exist by reading `capabilities` in
`$LocalAiRegistry` at runtime. Do not assume the set named here is complete —
it is a description of route *kinds*, not an inventory, and the inventory
grows. Count them at runtime rather than trusting a number written here; this
line previously said "fourteen" and was wrong within days.

## Chat model policy

`policy.chat_models_policy = uncensored-or-abliterated-required`.

Read the live model IDs from the registry. The declared local generator is
`provider.local` (Huihui-gemma-4-12B-it-abliterated via llama.cpp). Do not wire
aligned/refusal chat models into `generation.routes`. Embeddings, rerank, STT,
and the media synthesizers are not chat-refusal models — this policy does not
apply to them, and their declared winners stay as they are.

## Exact knowledge and legal scope contract

Do not infer scope from user folders or natural language. Resolve scope from
`$LocalAiRegistry` at runtime.

- `policy.single_model_root`, `policy.single_artifact_root`, `policy.single_vector_engine`, and `policy.single_control_plane` are authoritative.
- `storage.general_source_roots`, `storage.legal_work_product_root`, `storage.legal_evidence_roots`, and `storage.legal_evidence_policy` define what can be indexed.
- `legal_evidence_policy` must be `read-only`.
- Stable aliases must remain canonical: `knowledge` and `legal`.
- `storage.personal_knowledge_root` and `storage.legal_knowledge_root` are the only long-lived knowledge roots.

## Retrieval observability and regression gate

Use `ai.ps1 knowledge status|stale|explain|eval`. `explain` must retain query
variants, vector and reranker scores, selected chunks, source paths, and
model/index revisions. `eval` runs the synthetic golden set and reports
expected-document hit rate, recall@k, and MRR. A successful process is not an
accepted baseline: compare metrics to the retained thresholds and stop on a
meaningful regression.

Stable `/local/retrieve` and `/local/chat` gateway adapters remain loopback-only.
They may proxy only to declared local services and never silently fall back to
cloud.
