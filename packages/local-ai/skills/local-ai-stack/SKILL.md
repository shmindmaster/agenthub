---
name: local-ai-stack
description: Use when local model inference, RAG/retrieval, media generation, and legal/knowledge scope routing are required.
---

# Local AI stack

This is the operator skill for one user-owned Local-AI runtime. Its instructions
are host-neutral, but the supported operator interface is Windows PowerShell.
The skill's presence does not prove that it is installed on every agent host or
that the runtime is currently ready.

## Resolve the runtime

Resolve the root once. The environment override supports another machine; the
default for this workstation is `D:\Local-AI`.

```powershell
$LocalAiRoot = if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' }
$LocalAiControl = Join-Path $LocalAiRoot 'ai.ps1'
$LocalAiRegistry = Join-Path $LocalAiRoot 'registry.json'
```

After this bootstrap, resolve services, ports, models, indexes, storage roots,
and artifacts from `$LocalAiRegistry`. Examples below describe intent; embedded
paths or ports are not a second source of truth.

## Outcome-oriented discovery

Use this skill only after layered checks:

1. `& $LocalAiControl status` for current service state.
2. `& $LocalAiControl check` for the control-plane contract, or `check deep`
   when the requested task warrants the full deterministic smoke gate.
3. Confirm the requested route's services, model files, and stable alias—not
   only generic stack health.
4. For a heavy job, inspect GPU occupancy and active jobs. Reclaim only with
   task authority and only after identifying what it will unload.

Proceed only for the route whose checks passed:

- **chat + attachments** -> Open WebUI route.
- **knowledge/legal retrieval** -> RAG route.
- **media synthesis** -> ComfyUI/Creative-Lab route.
- **voice/STT** -> dedicated media runtime route.

## One control interface

`$LocalAiControl` is the only control plane for this capability.

```powershell
& $LocalAiControl status
& $LocalAiControl check [deep]
& $LocalAiControl start <target>
& $LocalAiControl stop <target>
& $LocalAiControl reclaim <minimum GiB>
& $LocalAiControl reindex <knowledge|legal|all> [--recreate] [--activate]
```

`start`, `stop`, `restart`, `clean`, `reclaim`, every `reindex`, media generation,
`--recreate`, and `--activate` mutate shared runtime state, consume shared GPU,
or write artifacts. Inspect the exact target and active jobs, then obtain the
authority required by the current task. Build a replacement collection without
`--activate`; activate only after point parity, retrieval acceptance, and
independent review pass.

All media and synthesis routes are also under the same interface:

```powershell
& $LocalAiControl image <single|batch>
& $LocalAiControl voice <qwen|chatterbox|verify>
& $LocalAiControl transcribe <audio-or-video-path>
& $LocalAiControl music <batch-json>
& $LocalAiControl motif <verify|single|batch>
```

Do not add a second control script or a parallel launcher for this capability.

## Route matrix

Read endpoint URLs and model IDs from `$LocalAiRegistry`; do not invent them,
pull ad-hoc models, or copy weights outside `policy.single_model_root`.

### 1) Model routes

- **Chat and assistant APIs**: Open WebUI calling the declared Local-AI API.
- **Local inference provider layer**: the declared Ollama service and optional
  on-demand llama.cpp capability.
- **Model contract source**: `$LocalAiRegistry` under `capabilities`.

### 2) RAG routes

- **Primary retrieval API**: the declared Jina embeddings, rerank, and
  multimodal service.
- **Vector store**: the single declared Qdrant service.
- **Persistent indexing contract**: the catalog at
  `shared\catalogs\corpus-v2.sqlite` under the resolved root feeds versioned
  Qdrant collections exposed through `knowledge` and `legal`. Older
  personal/legal SQLite databases are migration inputs only, not retrieval
  engines.
- **Index metadata contract**: `indexes` in `$LocalAiRegistry`.

### 3) Media routes

- **Image**: the declared image capability via `ai.ps1 image`.
- **Voice and TTS/STT**: the declared voice/STT capabilities via the control
  plane.
- **Video/music**: `ai.ps1 motif` and `ai.ps1 music`.

## Exact knowledge and legal scope contract

Do not infer scope from user folders or natural language. Resolve scope from
`$LocalAiRegistry` at runtime.

- `policy.single_model_root`, `policy.single_artifact_root`, `policy.single_vector_engine`, and `policy.single_control_plane` are authoritative.
- `storage.general_source_roots`, `storage.legal_work_product_root`, `storage.legal_evidence_roots`, and `storage.legal_evidence_policy` define what can be indexed.
- `legal_evidence_policy` must be `read-only`.
- Stable aliases must remain canonical: `knowledge` and `legal`.
- `storage.personal_knowledge_root` and `storage.legal_knowledge_root` are the only long-lived knowledge roots.

## Storage boundaries

| Layer | Source of truth | Allowed use | Do not |
|---|---|---|---|
| Runtime | declared services/volumes | process state and service-owned data | copy into product repositories |
| Catalog | `corpus-v2.sqlite` | provenance, parsing, checkpoints | use as a second retrieval engine |
| Retrieval | versioned Qdrant collections plus stable aliases | persistent corpus search | query an unreviewed replacement collection as canonical |
| Attachments | Open WebUI service-owned upload storage | current chat context | treat as persistent corpus ingestion |
| Artifacts | `policy.single_artifact_root` | generated media and validation evidence | write generated output into model/runtime/catalog roots |

## Open WebUI attachments vs persistent corpus retrieval

Treat these as separate storage behaviors:

- **Open WebUI attachments**: chat-uploaded files live in the Open WebUI runtime/data scope (docker `open-webui` volume) and are not equivalent to persistent knowledge corpus.
- **Persistent corpus retrieval**: only goes through `reindex` + Qdrant index/alias contract above.

Do not use Open WebUI native attachments as long-term retrieval source material.

To check the attachment path itself, upload `fixtures/openwebui-native-attachment.md`
from this package to a chat and ask for its verification phrase. A correct stack
answers `ORCHID-RIVER-7429` from the attachment. A pass covers extraction,
embedding, retrieval, and answering on the attachment route only — it is not
retrieval acceptance for the persistent corpus, which goes through `reindex` and
the Qdrant index/alias contract above. Keep the fixture out of every persistent
knowledge root: indexing it would put the needle in the haystack and leave a
check that can no longer fail.

## GPU scheduling and deterministic operation

- The stack policy is serialized GPU scheduling (`policy.gpu_heavy_jobs = serialized`).
- Before a heavy job: inspect active jobs and GPU occupancy, identify reclaim
  side effects, reclaim only if authorized, run one heavy job, then release its
  model allocation.
- Fail closed on concurrent heavy work unless the current task explicitly
  coordinates ownership of the shared GPU.

## Validation expectations for coding agents

Run deterministic validation before reuse:

```powershell
powershell -File "<loaded-skill-directory>\validate-local-ai-stack.ps1" -Root $LocalAiRoot
```

The validator checks:

- single control-plane contract,
- explicit `registry.json` policy and scope fields,
- declared service set,
- knowledge/legal stable aliases,
- and no accidental reintroduction of unsupported stack roots.

## Guardrails

- Do not pass `num_ctx` directly to Ollama; model context is model-owned.
- Do not copy or recreate external runtime control surfaces.
- Do not commit runtime paths, generated artifacts, private corpora, or model
  weights into a product repository. Personal capability checks use synthetic
  fixtures unless the task explicitly authorizes a registry-scoped source.
- Do not use `D:\AI-Platform` as a stack root or replacement registry.
- Do not restore removed legacy pipelines, model copies, or deprecated product-demo workflows.
