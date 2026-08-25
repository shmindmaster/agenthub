# Local-AI storage, GPU, and validation (progressive load)

Load for storage boundaries, GPU scheduling, validation, adoption, or guardrail detail.
Control plane remains `ai.ps1` / `$LocalAiControl`.

## Storage boundaries

| Layer | Source of truth | Allowed use | Do not |
|---|---|---|---|
| Runtime | declared services/volumes | process state and service-owned data | copy into product repositories |
| Catalog | `corpus-v2.sqlite` | provenance, parsing, checkpoints | use as a second retrieval engine |
| Retrieval | versioned Qdrant collections plus stable aliases | persistent corpus search | query an unreviewed replacement collection as canonical |
| Attachments | Open WebUI service-owned upload storage | current chat context | treat as persistent corpus ingestion |
| Artifacts | `policy.single_artifact_root` | generated media and validation evidence | write generated output into model/runtime/catalog roots |

### Reclaiming space in the WSL2 disk Qdrant lives in

Qdrant's named volumes sit inside Docker Desktop's data disk, a `.vhdx` under
`Docker\wsl\disk` that is a **separate** file from the `docker-desktop` distro's
own `ext4.vhdx` under `Docker\wsl\main`. Freeing space inside the guest — pruning
containers, images, or build cache — does not shrink that file. On an install
predating Docker's sparse-by-default behavior it only ever grows.

Two mechanisms, and they are mutually exclusive at any one moment:

- **Sparse flag** (`fsutil sparse setflag`, no elevation) lets the guest's TRIM
  punch holes, so future frees release automatically. It does **not** retroactively
  deallocate blocks already written, so setting it releases almost nothing at the
  time — the reclaim arrives over subsequent restarts as TRIM runs. Measured
  2026-08-25: 85.56 GB allocated at flag-set, 72.14 GB one restart later.
- **`diskpart compact vdisk`** (elevated, Docker and WSL fully stopped) reclaims
  everything at once, down to real usage.

The trap is that they collide: `compact vdisk` refuses a sparse file outright
("must be uncompressed and unencrypted and must not be sparse"). Clearing the flag
first works, but NTFS fills every hole with real zeros to do it, so the file jumps
back to full logical size before the compact shrinks it. Budget the free space for
that spike. The working order is clear flag → compact → set flag again; measured
86.41 GB → 47.16 GB in ~1 min.

Measure with `GetCompressedFileSizeW`, not `Get-Item .Length`. Once the file is
sparse the two diverge, and `.Length` reports the logical size — the number that
does not change no matter how much you reclaim.

Bring the stack back afterwards. Containers with `restart=unless-stopped` return
on their own; anything at `restart=no` does not, so record `docker ps` before
stopping. Local-AI's own host services (ollama, retrieval, local-ai-api) are not
containers and need `ai.ps1 start core --gpu-text` — without that flag the text
embedder silently comes back on CPU.

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
- **Music does not start ComfyUI.** `ai.ps1 music` uses the ACE-Step resident
  runtime (`music.ace-step`). `start comfyui` / `start media` is for image/motif
  only and will steal VRAM from ingest and TTS. See `references/music.md`.

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
