# Local-AI retrieval and routing (progressive load)

Load when the task needs RAG/Qdrant, chat model policy, or knowledge/legal scope.
Control plane remains `ai.ps1` / `$LocalAiControl`.

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
  `data\catalog\corpus-v2.sqlite` under the resolved root feeds versioned
  Qdrant collections exposed through the stable aliases `knowledge`
  (→ `knowledge_v1`) and `legal` (→ `legal_v1`). Older personal/legal SQLite
  databases are migration inputs only, not retrieval engines.
- **Index metadata contract**: `indexes` in `$LocalAiRegistry`.

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
