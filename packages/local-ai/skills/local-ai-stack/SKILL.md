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

## Layout

```text
models\chat | retrieve | generate
data\catalog | qdrant | artifacts | cache | secrets | runtime
runtimes\retrieve | media | llama | python
apps\retrieval | api
media\   # image/voice/motif/music/transcribe scripts
```

Verified against disk 2026-08-08. This is orientation, not authority — the
registry stays the source of truth for any path you act on.

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

The retrieval service's local admin credentials are auto-provisioned on first
`start retrieval` / `start core`: `ai.ps1` writes
`data\secrets\retrieval-admin-secrets.json` under the resolved root with a
restrictive ACL when it is absent. No manual environment variables are
required for a local run.

All media and synthesis routes are also under the same interface:

```powershell
& $LocalAiControl image <single|batch>
& $LocalAiControl voice <qwen|qwen-role|qwen-clone|qwen-*-batch|score|verify>
& $LocalAiControl catalog ["<voice alias>"]
& $LocalAiControl transcribe <audio-or-video-path>
& $LocalAiControl music <batch-json>
& $LocalAiControl motif <verify|single|batch>
```

Do not add a second control script or a parallel launcher for this capability.
**`ai.ps1 voice kokoro` is removed** and fails loudly.

## Voice TTS — FROZEN (Qwen3-TTS only)

> **Qwen3-TTS is the only production TTS family. `faster-qwen3-tts` is the only
> Qwen inference backend. 0.6B Base = default clone; 1.7B Base = premium clone;
> 0.6B CustomVoice = generic presets; 1.7B CustomVoice = directed/`instruct`;
> VoiceDesign = create then enroll. Full ICL + cached prompts + hot CUDA graphs.
> Kokoro removed. Stock `qwen_tts` / `Qwen3TTSModel` production route disabled —
> no silent fallback.**

Authoritative disk policy (do not fork a second catalogue into AgentHub):

- `$LocalAiRoot\data\artifacts\media\voice-corpus\PRODUCTION-VOICE-POLICY.md`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\VOICE-MAP.md`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\library.json`
- `$LocalAiRoot\data\artifacts\media\voice-corpus\AGENTS.md`

Architecture:

```text
YOUR VOICE BANK → QWEN VOICE ROUTER
  → 0.6B Base Fast (DEFAULT clone) | 1.7B Base Fast (PREMIUM)
  → 0.6B CustomVoice Fast (DEFAULT role) | 1.7B CustomVoice Fast (instruct)
  → 1.7B VoiceDesign Fast (FACTORY only)
  → faster-qwen3-tts CUDA Graphs → RTX 5060 Ti
```

Do **not** add Docker, vLLM, Triton, or FlashAttention for TTS speed. Native
Windows CUDA venv (`runtimes\media\voice-qwen-fast`) only.

### STOP — first-class voices (celebrity names are style labels)

| Display name | Canonical id | Default render |
| --- | --- | --- |
| **Sarosh** | `sarosh` | 0.6B Base Fast (identity-gated) |
| **Morgan Freeman-style** | `narrator-calm-authoritative` | 0.6B Base Fast |
| **Matthew McConaughey-style** | `narrator-conversational-charismatic` | 0.6B Base Fast |
| **Michael Caine-style** | `narrator-deliberate-mentor` | 0.6B Base Fast |
| **David Attenborough-style** | `narrator-natural-history-documentary` | 0.6B Base Fast |
| Relaxed Storyteller | `narrator-relaxed-storyteller` | 0.6B Base Fast |
| Documentary Scholar | `narrator-documentary-scholar` | 0.6B Base Fast |
| Technical Instructor | `narrator-technical-instructor` | 0.6B Base Fast |
| Aiden / Ryan / Uncle_Fu / Vivian / Serena / Dylan / Eric / Ono_Anna / Sohee | `role-*` | 0.6B CV Fast |

Never invent a new clone because “Morgan Freeman isn’t a folder name.” Resolve
via `ai.ps1 catalog "Morgan"` / `library.json` aliases. Public copy: **“-style”**
persona — not an impersonation claim. Voice id is stable; model size is only the
renderer (`preferred_tier=premium` → 1.7B, same id).

Former Kokoro / `smoke-narrator` / `af_heart` → **`role-aiden`** (retired alias
with `redirect_to`). Do not call Kokoro.

### Router

1. Existing clone → `qwen-clone` 0.6B Fast → need premium? → `--premium` (1.7B)
2. Generic preset → `qwen-role` 0.6B CustomVoice Fast
3. Preset + acting/`--instruction` → 1.7B CustomVoice Fast (0.6B lacks full NL instruct)
4. Brand-new persona → `qwen` VoiceDesign Fast → approve → enroll → Base Fast thereafter

```powershell
& $LocalAiControl voice qwen-clone --voice narrator-calm-authoritative --text "…" --out out.wav
& $LocalAiControl voice qwen-clone --voice sarosh --premium --text "…" --out out.wav
& $LocalAiControl voice qwen-role --speaker Aiden --text "…" --out out.wav
& $LocalAiControl voice qwen-role --speaker Ryan --instruction "restrained anger, deliberate pace" --text "…" --out out.wav
```

**Invoke with the call operator, never `pwsh -File`.** `--out` prefix-matches
`-OutVariable`/`-OutBuffer`. From non-PowerShell, pass text through the
environment:

```powershell
pwsh -NoProfile -Command "& '<root>\ai.ps1' voice qwen-clone --voice $env:V --text $env:T --out $env:O"
```

If anything requests stock `qwen_tts` / slow backend:

```text
ERROR: Slow Qwen TTS backend disabled.
Use faster-qwen3-tts.
```

Fail → retry fast → new seed → escalate 0.6→1.7 Fast → STOP+LOG. Never silent
stock fallback. One bad WAV ≠ abandon the backend.

### Sarosh (identity-gated)

Expressiveness = style WAV + `.txt` from
`voices\sarosh\styles-20260815\` (default `02_explaining`) — **not** free-text
`instruct`. Profile locks `do_sample: false`. `reference.wav` is the identity
score anchor only.

```powershell
& $LocalAiControl voice qwen-clone --voice sarosh `
  --reference "<root>\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815\02_explaining.wav" `
  --ref-text "<sidecar txt>" --text "…" --out out.wav
& $LocalAiControl voice score --voice sarosh <file-or-dir>
```

Do not recreate Chatterbox / `sarosh-qwen` / x-vector-only / meeting-fine-tune
profiles. Do not fix pronunciation by respelling text (fails identity floor).

### Ops

- Full **ICL** for enrolled clones (ref WAV + exact transcript). x-vector only
  with an explicit reason.
- Cache clone prompts once per process; keep the model hot (warmup / CUDA graphs
  once; no per-line reload).
- Offline/episode: **non-streaming**; group jobs by model then voice. Resident
  default = 0.6B Base; load other variants for grouped jobs.
- Live UI: stream chunk ≈ 4–8.
- Advanced sampling (`temperature`, `top_k`, …) under Advanced only — don’t
  randomize per line; use 1.7B CV `instruct` for acting.
- Languages (Qwen): Chinese, English, Japanese, Korean, German, French, Russian,
  Portuguese, Spanish, Italian.

### Specialty engines

`voice.voxcpm2`, `voice.indextts25`, `voice.bestof`, `voice.performance` remain
specialty — not production defaults. Do not expand the production TTS family
unless Qwen fails a measured requirement.

### Building or extending the owner voice corpus

Training and reference material is assembled by the refinery, never by hand:

```powershell
& $LocalAiControl corpus <sources|ingest|map|calibrate|select|transcribe|classify|report>
```

Source audio is read-only. Path denylist fails closed. Mined pools cannot reach
Gold without provenance. New VoiceDesign personas: generate once → enroll into
`library.json` with aliases → produce with Base clone thereafter.

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

### 3) Media routes

- **Image**: the declared image capability via `ai.ps1 image`.
- **Voice and TTS/STT**: Qwen3-TTS via `faster-qwen3-tts` only (`voice.clone` /
  `voice.role` / `voice.design`) plus STT; see Voice TTS section above. Kokoro
  / `audio.tts.bulk` removed.
- **Video/music**: `ai.ps1 motif` and `ai.ps1 music`.

Resolve which media capabilities exist by reading `capabilities` in
`$LocalAiRegistry` at runtime. Do not assume the set named here is complete —
it is a description of route *kinds*, not an inventory, and the inventory
grows. Count them at runtime rather than trusting a number written here; this
line previously said "fourteen" and was wrong within days.

## Chat model policy

`policy.chat_models_policy = uncensored-or-abliterated-required`.

Read the live model IDs from the registry; the declared kinds are an
abliterated Qwen3 for text and an abliterated Qwen3-VL for vision. Do not wire
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
- every service the registry itself marks `required: true` — derived, not a
  list frozen in the validator, so services may be added or retired without
  editing it,
- the retrieval spine (`retrieval.text`, `retrieval.reranker`), because the RAG
  route above cannot resolve without it,
- the *shape* of every declared capability — not its membership,
- knowledge/legal stable aliases,
- and no accidental reintroduction of unsupported stack roots.

It deliberately does not check which image, voice, STT, video, music, or
provider capabilities exist. That inventory is open. See below.

## Adopting newer models and capabilities

The declared inventory is a snapshot, not a ceiling. Researching and adopting
newer or alternative open-source models is expected work, not an exception —
prefer investigating a current option over settling for whatever is already
installed. Nothing in this skill or its validator should be read as a closed
list of what the stack may run.

What an adoption has to satisfy is the contract, not a whitelist. Add the
capability to `capabilities` in `$LocalAiRegistry` with the same shape the
existing entries use:

- `id`, `category`, `status` on every entry;
- for anything `status: enabled`, a `verification` and either an `entrypoint`
  or `required_files`, so presence can actually be confirmed rather than
  assumed;
- `model_identity` with `revision` and a `fingerprint` where the weights have
  an upstream identity worth pinning;
- `minimum_vram_gib` where the capability competes for the GPU.

Then the standing policy still applies, and these are the real constraints:

- weights land under `policy.single_model_root`; output under
  `policy.single_artifact_root`;
- `policy.gpu_heavy_jobs = serialized` — a new heavy model does not get to run
  concurrently with another;
- `policy.external_data_transmission = explicit-approval-required` covers
  evaluating a hosted or remote model, and covers uploading local corpus
  material to one;
- `policy.single_vector_engine` stays Qdrant; a new embedding model means a new
  versioned collection promoted through the alias contract, not a second
  retrieval engine.

Retire a capability by removing or disabling its registry entry. Because the
validator derives from the registry rather than a pinned list, both adopting
and retiring are registry edits — neither requires changing this skill.

## Guardrails

- Do not pass `num_ctx` directly to Ollama; model context is model-owned.
- Do not copy or recreate external runtime control surfaces.
- Do not commit runtime paths, generated artifacts, private corpora, or model
  weights into a product repository. Personal capability checks use synthetic
  fixtures unless the task explicitly authorizes a registry-scoped source.
- Do not use `D:\AI-Platform` as a stack root or replacement registry.
- Do not restore removed legacy pipelines, model copies, or deprecated product-demo workflows.
