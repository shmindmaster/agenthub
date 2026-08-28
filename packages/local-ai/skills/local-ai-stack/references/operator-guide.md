# Local-AI operator guide

Local-AI is the workstation control plane at `D:\Local-AI`. AgentHub owns the
portable agent policy; `registry.json` owns executable runtime truth. When prose
and the registry disagree, the registry wins.

Product-specific media commands and acceptance rules belong in each product
runbook. This guide intentionally contains no product, client, or customer workflow.

## Start here

```powershell
$LocalAiRoot = if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' }
$ai = Join-Path $LocalAiRoot 'ai.ps1'
& $ai status
& $ai check
& $ai doctor --json
& $ai capabilities --json
```

- `status` reports listener/readiness state.
- `check` validates the legacy runtime and file contract and always emits a result.
- `doctor` is read-only and diagnoses registry, GPU, storage, models, services,
  listeners, Qdrant, leases/jobs, generated docs, and AgentHub provenance.
- `capabilities` and `capability <id>` expose the machine-readable inventory.

## Operating rules

- Keep `D:\Local-AI` non-Git. Never initialize or push it.
- Keep weights under `D:\Local-AI\models` and artifacts under the registry's
  declared artifact root.
- Use `ai.ps1`; do not invent a second launcher or bypass the registry.
- Heavy generation is serialized through durable jobs and one reconciled GPU
  lease system. Unknown GPU processes block work and are never killed automatically.
- Inputs remain referenced and hashed unless a specific workflow explicitly copies
  them. Do not place credentials or private source bytes in a job manifest.
- Local-only is the default. There is no silent cloud fallback.
- Qdrant for this stack is `:16333`; `:6333` is a different instance.
- Owner voice stays local and requires explicit `--owner-voice` job metadata plus
  identity QA before delivery. Do not phonetic-respell owner narration.

## Durable jobs and routing

```powershell
& $ai route --intent image --quality preview --json
& $ai job submit image.mnemonic --quality standard --wait -- --prompt 'synthetic test' --out D:\Local-AI\data\artifacts\smoke.png
& $ai job list --json
& $ai job inspect <job-id> --json
& $ai job cancel <job-id>
& $ai job retry <job-id>
& $ai job resume <job-id> --stage qa
```

Legacy heavy commands remain blocking, but now pass through the same queue:

```powershell
& $ai image single --prompt 'synthetic fixture' --out out.png
& $ai voice qwen-role --speaker Aiden --text 'Synthetic test.' --out out.wav
& $ai transcribe out.wav
```

Quality tiers are stable: `preview`, `standard`, `high`, and
`identity-critical`. Privacy and quality compatibility are checked at routing,
job submission, and gateway boundaries.

## Retrieval and QA

```powershell
& $ai knowledge status --json
& $ai knowledge stale --json
& $ai knowledge explain 'query text' --index knowledge --json
& $ai knowledge eval --json
& $ai qa <artifact-path-or-job-id> --profile high --json
```

Knowledge evaluation records expected-document hit rate, recall@k, MRR, selected
chunks, source paths, vector/reranker scores, and model/index revisions. QA
dispatches checks appropriate to the artifact: media integrity, ASR/transcript,
loudness, black frames, structural lip-sync evidence, and owner identity only for
explicit owner-voice jobs.

## Stable loopback adapters

The gateway exposes `/local/chat`, `/local/retrieve`, `/local/voice`,
`/local/image`, `/local/asr`, and `/local/jobs`. Direct service ports remain
available for compatibility and health checks. All services bind loopback; an
external listener is a doctor warning that must be investigated.

## Documentation and recovery

```powershell
& $ai docs check --json
& $ai docs sync --json
```

Generated inventory regions bind the registry revision and AgentHub commit. Use the
pre-change release receipt under
`D:\Local-AI\data\artifacts\platform-releases` for rollback evidence; do not
restore individual files without checking their hashes and current job/service state.

Specialist behavior is documented in `references/ops.md`, `retrieval.md`,
`voice.md`, `image.md`, `video.md`, and `music.md`.

<!-- LOCAL-AI:GENERATED:START -->
Generated from registry revision `2026-08-28.1` and AgentHub provenance `68bbc126a2a7a7185848ab8564946036742de5d7`. Do not edit this block.

### Services

| Service | Port | Required | Health |
| --- | ---: | :---: | --- |
| `ollama` | 11434 | yes | `http://127.0.0.1:11434/api/tags` |
| `qdrant` | 16333 | yes | `http://127.0.0.1:16333/readyz` |
| `retrieval` | 8790 | yes | `http://127.0.0.1:8790/health` |
| `local-ai-api` | 8787 | yes | `http://127.0.0.1:8787/api/health` |
| `open-webui` | 3080 | yes | `http://127.0.0.1:3080/health` |
| `gateway` | 80 | yes | `http://127.0.0.1/health` |
| `hermes` | 9119 | no | `http://127.0.0.1:9119` |
| `comfyui` | 8188 | no | `http://127.0.0.1:8188/system_stats` |
| `invokeai` | 9090 | no | `http://127.0.0.1:9090/api/v1/app/version` |
| `llama-cpp` | 10000 | no | `http://127.0.0.1:10000/health` |
| `voice-api` | 8792 | no | `http://127.0.0.1:8792/health` |
| `tts-studio` | 8791 | no | `http://127.0.0.1:8791/api/state` |
| `platform-api` | 8794 | yes | `http://127.0.0.1:8794/health` |

### Capabilities

| Capability | Category | Surface | VRAM GiB | Resource |
| --- | --- | --- | ---: | --- |
| `retrieval.text` | retrieval | primary | 2 | `gpu0-retrieval` |
| `retrieval.reranker` | retrieval | primary | 2 | `gpu0-retrieval` |
| `retrieval.omni` | retrieval | primary | 5 | `gpu0-retrieval` |
| `image.mnemonic` | image | primary | 12 | `gpu0-exclusive` |
| `image.invoke-canvas` | image | primary | 12 | `gpu0-exclusive` |
| `voice.role` | voice | primary | 4 | `gpu0-exclusive` |
| `voice.design` | voice | primary | 8 | `gpu0-exclusive` |
| `voice.clone` | voice | primary | 4 | `gpu0-exclusive` |
| `audio.stt` | audio | primary | 9 | `gpu0-exclusive` |
| `audio.understanding` | audio | primary | 10 | `gpu0-exclusive` |
| `video.motif-q8` | video | primary | 14 | `gpu0-exclusive` |
| `video.lipsync.latentsync-1.5` | video | primary | 8 | `gpu0-exclusive` |
| `video.portrait.liveportrait` | video | specialty | 6 | `gpu0-exclusive` |
| `media.facefix.facefusion` | media | specialty | 4 | `gpu0-exclusive` |
| `music.ace-step` | music | primary | 10 | `gpu0-exclusive` |
| `provider.local` | llm | primary | 13 | `gpu0-llm` |
| `retrieval.legal` | retrieval | specialty | 5 | `gpu0-retrieval` |
| `voice.voxcpm2` | voice | specialty | 8 | `gpu0-exclusive` |
| `voice.indextts25` | voice | specialty | 6 | `gpu0-exclusive` |
| `audio.identity` | audio | specialty | 2 | `gpu0-light` |
| `corpus.refinery` | audio | specialty | 2 | `gpu0-light` |
| `voice.performance` | voice | specialty | 0 | `none` |
| `voice.bestof` | voice | specialty | 8 | `gpu0-exclusive` |
<!-- LOCAL-AI:GENERATED:END -->
