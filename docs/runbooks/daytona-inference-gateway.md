# Daytona Spot Inference Gateway (NVIDIA + AMD)

Permanent inference gateway and unified NVIDIA/AMD Daytona spot GPU operations for AgentHub coding agents.

## Architecture

- **Permanent HTTPS Endpoints:**
  - **Inference API:** `https://inference.shtrial.com/v1` (and Media Lab: `https://inference.shtrial.com/v1/media`)
  - **Hosted Studio UI:** `https://studio.shtrial.com` (`AgentHub Studio`, Open WebUI pre-wired to `http://agenthub-litellm:4000/v1` via dedicated Studio virtual key for all 5 Daytona `agent-*` aliases + live `cloud-*` aliases, with both `daytona_media_lab` (`scripts/daytona-inference/studio/openwebui_media_lab_tool.py`) and entity-routed `cloud_media_apis` (`scripts/daytona-inference/studio/openwebui_cloud_media_tool.py`) tools + `/media-dl/*` direct attachment downloads + native Tavily web search). Both `/media-out/*` and `/media-dl/*` are gated behind Caddy `forward_auth` against Open WebUI's `/api/v1/auths/` endpoint (unauthenticated HTTP 401, cookie-authenticated HTTP 200), `CORS_ALLOW_ORIGIN` is locked to `https://studio.shtrial.com`, public and OAuth self-signups are disabled (`ENABLE_SIGNUP=false`, `ENABLE_OAUTH_SIGNUP=false`), the owner's own address is the sole Studio admin user, and **Clerk Production OIDC SSO** is wired via `OPENID_PROVIDER_URL=https://clerk.shtrial.com/.well-known/openid-configuration` (`AgentHub Studio` Clerk app `app_3McOECeqYVkZi3csVBN8EUOZS6F`, `https://accounts.shtrial.com`, PKCE `S256`, `OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true`, `ENABLE_OAUTH_PERSISTENT_CONFIG=false`, with Clerk instance allowlist enforcement on sign-up and sign-in restricted to that same account).
  - **Cloud Media & LLM Credit Scope:** `AGENTHUB_INFERENCE_KEY` (used by coding agents) remains strictly scoped to the 5 self-hosted `agent-*` Daytona models; the `agenthub-studio` virtual key exposes verified `cloud-openai-*`, `cloud-anthropic-*`, `cloud-azure-*` (`mt-foundary-resource`), `cloud-openrouter-*`, `cloud-deepseek-*`, `cloud-zai-glm-5.4`, and `cloud-nvidia-nemotron-120b-vl` alongside `agent-*` (skipping quota-exhausted Qwen/MiMo Token Plan until reset). `cloud_media_apis` enforces Notion Film Desk / Linear `BIZ-22` credit routing (Deepgram Flux default stock voice on MahumTech, AssemblyAI consented clones for ABACare, OpenAI `gpt-image-2.6-flare` / Azure `gpt-image-2.5-flare` / Runware / OpenRouter images, Runware API credit video/music, Pexels free stock photos/videos, Reducto PDF parsing, ElevenLabs exception-only requiring a written reason; Gemini AI Studio paused until `2026-12-01` and Runway/Higgsfield frozen).
  - **Gateway Host:** Dedicated persistent DigitalOcean droplet `sh-inference` (`64.225.2.73`, `s-2vcpu-4gb`, `nyc3`, firewall `sh-inference-fw`), migrated off `sh-forge` on `2026-11-25` ahead of `sh-forge`'s `2026-12-01` teardown (`SH_FORGE_SSH_HOST=sh-inference`). DNS `A` records (`inference`, `studio`, `comfy`) are hosted in DigitalOcean DNS (`shtrial.com`), all pointing at `sh-inference`.
  - Reverse-proxied through Caddy on `sh-inference`, preserving `/v1/chat/completions`, `/v1/responses`, `/v1/models`, and `/health/liveliness` on LiteLLM (`127.0.0.1:4000`, gated by Bearer auth), proxying `handle_path /v1/media/*` to Slot 2 `:8189` (always gated by the `AGENTHUB_INFERENCE_KEY` Bearer token, even from the owner IP, injecting `x-daytona-preview-token` and the media gateway token), and restricting admin endpoints (`/ui`, `/model/*`, `/key/*`) to `<OWNER_IP>`.
  - Backed by LiteLLM + PostgreSQL (`scripts/daytona-inference/gateway/`), preserving model aliases without ever rewriting coding-agent configs or DNS on spot eviction.
  - Pre-`2026-12-01` migration record off `sh-forge`: see [MIGRATION-2026-12-01.md](../../scripts/daytona-inference/gateway/MIGRATION-2026-12-01.md).
- **Dual-MI355X Spot Architecture (2/2 Max GPU Slots):**
  - **Slot 1 (`engineering` role, `agenthub-engineering`):** Single MI355X (288 GB CDNA4 `gfx950`) running both models on `llama-server` HIP with FlashAttention and GPU-resident KV (`opencode-agent-weights`, `/mnt/opencode-weights`): `Qwen3.8-27B-Ultimate-Heretic-2.1ARA-MTP-Q8_0` plus `mmproj-BF16` on `:8001` (262144 ctx, `--parallel 4`), and `Inkling-2-Mini-Uncensored-Q8_0` plus `mmproj-BF16` on `:8002` (1048576 ctx, `q8_0` KV cache, `--parallel 2` with a 1-slot fallback), each restarting on its own if it crashes. Serves `agent-specialist`, `agent-fast`, `agent-vision`, `agent-flagship`, and (after `retire-legacy-turbo`) `agent-turbo`. Both slots are vision-capable.
    - **Live-verified 2026-11-25 through `https://inference.shtrial.com/v1`** (operator run, previous FP8 + Flash-Next pair): all five aliases answered code and tool-call requests, vision worked, and a 112k-token recall test passed. Measured throughput: flagship 65-79 tok/s, 27B about 170 tok/s. VRAM in use was 279.6 of 308.9 GB as `rocm-smi` reports it (288 GiB). The dual-Q8_0 + Inkling-2-Mini swap and the VoxCPM2 media addition are committed but **not yet live-verified**; run the five-alias check on the next `up engineering` before advertising them.
  - **Slot 2 (`media` role, `agenthub-media`):** Single MI355X (288 GB) on `agenthub-media-weights` (`/mnt/media-weights`), running ComfyUI (`127.0.0.2:8188`) + Media Gateway (`:8189`, `/healthz` & `/v1/info`) behind `https://inference.shtrial.com/v1/media/*` (`<MEDIA_PREVIEW_URL>` upstream), with the native ComfyUI Web UI exposed at `https://comfy.shtrial.com` through the same Caddy `forward_auth` gate as Studio. Three virtualenvs: `venv` (ComfyUI, gateway, SOV-Transcribe, LFM3-Omni, Whisper), `venv-qwen` (Qwen3-TTS, pinned `transformers` 4.57.3) and `venv-voxcpm` (VoxCPM2 2.0.3, 48 kHz Voice Design and zero-shot/transcript cloning). **Live-verified end to end 2026-11-25 (operator run, see "Media Lab Verification" below); VoxCPM2 and `comfy.shtrial.com` were verified in a later burst on the same day.** The gateway and worker sources (`gateway.py`, `audio_worker.py`, `models.json`) live outside this repository in `MEDIA_STUDIO_ROOT\gpu-gen\server`; the client only sends `authorization_profile` and the server enforces it. The box was released after the run, so `/v1/media` answers 502 until `gpu.py up media` and `gpu.py caddy-media` have run again.
- **Permanent Model Aliases (`registry/inference-providers.json`):**
  - `agent-fast`: 27B Heretic MTP Q8_0 routine/exploration (`low` default reasoning, 262144 ctx / 32768 output)
  - `agent-specialist`: 27B Heretic MTP Q8_0 general engineering + vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-vision`: 27B Heretic MTP Q8_0 browser/desktop/media vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-turbo`: the legacy H200 `qwen38-turbo-q6k` (`medium` default reasoning, 65536 ctx / 49152 in / 16384 out, which is what the registry advertises). `retire-legacy-turbo` moves the alias to Slot 1 `:8002` (Inkling-2-Mini, 1048576 ctx / 32768 output); raise the registry and Factory limits for `agent-turbo` in the same change that runs it, not before
  - `agent-flagship`: Inkling-2-Mini Q8_0 flagship reasoning with vision (`medium` default reasoning, 1048576 ctx / 32768 output, `q8_0` KV cache; `Q8_0` on MI355X/B300/B200, explicit `--allow-q6-fallback` on H200)
- **Hard Operating Constraints:**
  - Maximum **2** GPU instances combined across NVIDIA and AMD, **1** GPU per instance. While `qwen38-turbo-q6k` is live it counts as one of the two, so only one MI355X slot (engineering or media) can run next to it; both together need `retire-legacy-turbo` first.
  - **Spot-only** (`spot=True`); never falls back to on-demand. A box that comes back non-spot or on a different GPU than requested is deleted.
  - **TTL is always set** at create time and capped: `--ttl` and `extend` accept 1 to `policy.maxTtlMinutes` (480) minutes, default 120.
  - Protected live sandbox `qwen38-turbo-q6k` and protected volume `llm-models` are never touched by `up`/`down`/`extend`/`save-cache`; `retire-legacy-turbo` refuses unless `agenthub-engineering` is `STARTED`, was created at least 6 hours ago (`MIN_ENGINEERING_UPTIME_HOURS`, read from `createdAt`; a missing `createdAt` also refuses) and both `agent-specialist` and `agent-flagship` pass live verification on `https://inference.shtrial.com/v1`.
  - No silent fallback to paid providers or different checkpoints on unavailable aliases.

## Spot Reliability (measured 2026-11-25)

- Daytona evicted both MI355X spot boxes it ran on 2026-11-25 (`020c5f08` after 42 minutes, `0876ca45` after 28 minutes) while spot MI355X capacity showed about 200 free. A `capacity` count does not predict an eviction.
- The H200 spot box `qwen38-turbo-q6k` has run for more than 14 hours.
- An engineering boot takes about 18 minutes from the weights volume.
- So the MI355X slots are on-demand bursts, not an always-on lane, and the H200 box stays. `retire-legacy-turbo` has **not** been run; it needs engineering to have been up 6 hours, and a live check on a young box would have left every alias dead 20 minutes later.
- After any eviction run `gpu.py reconcile`. It prunes aliases whose sandbox is gone (four dead aliases were pruned on 2026-11-25) and re-registers `agent-turbo` on the live H200 box.

## Media Lab Verification (2026-11-25)

Operator run through `https://inference.shtrial.com/v1/media` on a spot MI355X, after the box booted from the filled volume in about 9.5 minutes (257 GB staged in about 5.5 minutes, the two Python environments restored from a 2.1 GB archive on the volume).

- **Every job type passed.** Gateway timings: image 28 s cold and 8 s warm; image to video 39 s (55 s the first time); text to speech 16 s; SOV-Transcribe 37 s with the exact text back; Whisper 8 s; music 9 s; talking video 67-73 s; research image 18 s; research image edit 59 s. Straight to the box (no gateway) the cold image took 71.7 s.
- **Talk uses its reference image** (checked with a generated portrait). Its burnt-out first frame was fixed in the server's graph by repeating the first latent and dropping three frames.
- **Authorization is enforced by the server:** no token or a wrong token 401 (`/healthz` on the gateway needs the key too, like every media path); a bad `authorization_profile` 400; a research model under the commercial profile or with no profile 403; commercial `image_edit` 400 because no commercial edit model is installed.
- **Limits to plan for.** Video is made in fixed 77-frame chunks, so it can outlast short speech. One upload hit a transient TLS error and passed on rerun; the client retries connection-level failures (and 502/503/504 on reads) three times, but a script that uses the API directly should retry too.
- **Run it as a burst.** MI355X spot boxes can be evicted (see Spot Reliability), so treat the media lab as a burst: `up media`, `caddy-media`, work, `down media`.

## GPU Lifecycle Commands

Run from Windows with `DAYTONA_API_KEY` set:

```powershell
$gpu = "$env:USERPROFILE\.config\opencode\daytona\gpu.py"
python $gpu capacity                       # live NVIDIA + AMD spot inventory
python $gpu status                         # active GPUs (N/2) + gateway aliases
python $gpu doctor                         # credentials, volumes, protected box, gateway health
python $gpu up engineering --gpu MI355X    # Slot 1 dual llama-server (:8001 27B Heretic, :8002 Inkling)
python $gpu retire-legacy-turbo            # gated cutover once Slot 1 is live-verified
python $gpu up media --gpu MI355X          # Slot 2 media lab (:8189) on agenthub-media-weights
python $gpu prefill media                  # fill agenthub-media-weights from Hugging Face on a CPU box (no GPU)
python $gpu caddy-media                    # update sh-inference Caddy /v1/media/* and comfy.shtrial.com upstreams
python $gpu up specialist --gpu auto       # legacy single-slot Qwen 27B FP8
python $gpu up flagship --gpu auto         # legacy single-slot Flash-Next Q8_0
python $gpu up flagship --gpu H200 --allow-q6-fallback
python $gpu extend engineering 120         # reset wall-clock TTL (1-480 minutes)
python $gpu reconcile                      # prune evicted backends & re-sync live turbo
python $gpu down media                     # delete managed sandbox
python $gpu save-cache specialist          # persist /root/.cache/{vllm,flashinfer} to opencode-agent-weights
```

Set `SH_FORGE_UPDATE=1` when running `gpu.py up media` (or run `gpu.py caddy-media`, `--dry-run` first) to rewrite the `inference.shtrial.com` and `comfy.shtrial.com` blocks of `/opt/forge/caddy/Caddyfile` from the template in `scripts/daytona-inference/gateway/Caddyfile.snippet`. The `<OWNER_IP>`, `<MEDIA_PREVIEW_URL>`, `<AGENTHUB_INFERENCE_KEY>`, `<MEDIA_PREVIEW_TOKEN>` and `<MEDIA_GATEWAY_TOKEN>` placeholders are filled at run time and never stored in git-tracked files; the rendered keys do sit in the Caddyfile on `sh-inference`. Each site block is replaced, so any hand-added directive inside `inference.shtrial.com` or `comfy.shtrial.com` is lost. The file is written in place, not by rename, because the Caddy container bind-mounts that one file and a rename would leave it reading the old inode (checked: host and container hashes are equal after the update). If `caddy validate` or the reload fails, the previous Caddyfile is written back without a reload.

`/v1/media/*` always needs `Authorization: Bearer <AGENTHUB_INFERENCE_KEY>`; the owner IP alone is not enough. That is the same key every coding agent holds, so anyone with it can queue media jobs on the GPU.

## Boot Path and Persisted Assets

- **Boxes boot from stock registry images, not custom snapshots.** Daytona cannot build a custom snapshot over 20 GB, so the AMD roles use `rocm/vllm` (engineering) and `rocm/pytorch` (media) and the recipes install what is missing at boot: `llama-server` is built once for `gfx950` and cached as a tarball under `/mnt/opencode-weights/bin/`, and ComfyUI plus its Python environment are bootstrapped on the media box. Only the H200 CUDA roles have snapshots, listed below. `catalog.json` carries no Dockerfile for the engineering or media images because none is built.
- **Weights are staged to local disk first, in parallel.** On the first boot a model downloads from Hugging Face to local disk (`/opt/models/...` for engineering, `/opt/gpu-gen/weights` for media, symlinked into ComfyUI), then a copy is written to the S3-backed volume (`/mnt/media-weights/weights`; the media recipe lists which files each pinned revision holds in `ready-<rev>.json`). On later boots the files are copied from the volume to local disk, 4 at a time, skipping any file whose size already matches, so an interrupted boot resumes. A volume copy is only trusted when its `ready.json` size manifest matches; a failed copy to the volume is a warning, and the next boot downloads again.
- **Prefill the media volume once, without a GPU.** `gpu.py prefill media` starts a 4 vCPU CPU box (`python:3.12-slim`, ephemeral, hard TTL 90 minutes by default, auto-stop 60) with the volume mounted, uploads `HF_TOKEN` (or `secrets/hf.token`) and `models.json` from the media server directory, and runs `recipes/prefill-media.py`, which streams every pinned Hugging Face file straight onto the volume (8 files at a time, files already the right size are skipped, so a rerun resumes) and writes each repo's `ready-<revision>.json` only after all of its files arrived. The box is deleted in a `finally`, the token is never printed, and the Authorization header is dropped when Hugging Face redirects to a CDN host. A GPU boot then copies from the volume instead of downloading; the full set (about 276 GB) took about 9 minutes on the first run. The script's offline logic and the box lifecycle are covered by `Test-InferenceProviders.ps1`; the redirect handling has not been run against a live download.
- **The volume holds a copy, not the working set.** Servers read from local disk; the volume (about 100 MB/s per read stream) exists to avoid re-downloading.

To minimize Spot recovery startup time (avoiding cold container image pulls, 29 GB Hugging Face weight downloads, and ~4.5 minutes of `torch.compile` + DeepGEMM SM90a kernel compilation):

- **Weights & JIT Cache Volume (`opencode-agent-weights`, mounted at `/mnt/opencode-weights`):**
  - `/mnt/opencode-weights/specialist/`: verified `orcarouter/Qwen3.8-27B-Uncensored-FP8` weights (`config.json` + 7 shards).
  - `/mnt/opencode-weights/caches/vllm-0.24.0-H200.tar.gz` (+ `.sha256`): persisted `/root/.cache/vllm` and `/root/.cache/flashinfer` compiled kernels, restored automatically by `recipes/serve-vllm-cuda.sh` before `exec vllm serve`.
- **Reusable `ACTIVE` Daytona GPU Snapshots (in ABACare AI LLC org):**
  - `agenthub-vllm-cuda-0-24-0-h200` (`vllm/vllm-openai:v0.24.0` + `huggingface_hub` + `hf_xet`, entrypoint `sleep infinity`)
  - `agenthub-llama-cuda-h200` (`ghcr.io/ggml-org/llama.cpp:server-cuda` + `python3` + `hf_xet`, entrypoint `sleep infinity`)
  - `gpu.py up` checks `resolve_active_snapshot()` first and boots directly via `CreateSandboxFromSnapshotParams`, falling back automatically to `CreateSandboxFromImageParams` for GPUs/backends without an active snapshot (all AMD `MI355X` roles and the media role). Engineering and media are MI355X-only: the CUDA variants of those two roles were removed because their recipes cannot boot from the stock images (the engineering fallback never started the flagship, and `nvidia/cuda` ships no Python or PyTorch for the media bootstrap).

## What Changes Next Time (Zero-DNS Spot Recovery vs. Gateway Migration)

- **Spot GPU eviction or expiry:** Requires **zero DNS updates** and **zero coding-agent configuration changes**. Run `python $gpu up engineering --gpu MI355X` (or `recover engineering`; `specialist` for the legacy single-slot role), which boots from snapshot/persisted weights/JIT cache and updates LiteLLM's PostgreSQL route table behind `https://inference.shtrial.com/v1`.
- **Gateway host migration (before `2026-12-01` `sh-forge` teardown):** Copy `/opt/forge/inference-gateway/` + `pg_dump` to the new persistent CPU host, start Compose + Caddy, and update **one** DigitalOcean DNS `A` record (`inference.shtrial.com -> <NEW_IP>`). Still **zero coding-agent changes**.

## Daytona Environment Keys

- `DAYTONA_API_KEY`: **ABACare AI LLC** organization (default used by `gpu.py`, `DAYTONA_ORG` for all GPU inference & portfolio workloads).
- `DAYTONA_V2_API_KEY`: **ABACare AI LLC** SDK v2 access key.
- `DAYTONA_API_KEY_SAROSH`: **Sarosh Hussain Personal** account key (separate; only use when explicitly targeting personal credits).

## Multi-Agent Provider Rollout & Drift Audit

Additive rollout (`agenthub-daytona`) preserves every host's existing defaults, subscriptions, and auth profiles:

```powershell
pwsh -NoProfile -File .\scripts\Sync-InferenceProviders.ps1 -Audit
pwsh -NoProfile -File .\scripts\Sync-InferenceProviders.ps1 -Apply
```

### Selecting Daytona Models (Opt-In)

- **OpenCode:** `opencode run --model agenthub-daytona/agent-specialist#everyday ...` (uses `{file:.../secrets/inference.key}` when present; defaults `qwen-token-plan/qwen3.8-max` / `qwen3.8-flash` unchanged)
- **Codex CLI:** `codex -p daytona-specialist ...` (standalone `~/.codex/daytona-*.config.toml` profiles) or `codex -c 'model_provider="agenthub-daytona"' -m agent-specialist` (`gpt-6.2-sol` + ChatGPT auth unchanged)
- **Factory Droid:** `droid exec -m custom:daytona-specialist ...` or select `custom:daytona-specialist` / `custom:daytona-flagship`
- **Grok Build:** `grok --model agenthub-daytona-specialist ...`
- **Copilot CLI:** `copilot --model agenthub-daytona/agent-specialist`
- **VS Code Insiders:** Language Model Picker → `AgentHub Daytona Spot`
- **Kilo Code:** `kilo run --model agenthub-daytona/agent-specialist ...` (`mimo/mimo-v2.6-pro` unchanged)
- **Cline:** `cline -P openai-compatible -m agent-specialist ...` (uses Cline `3.0.74`'s built-in `openai-compatible` provider pointing at `https://inference.shtrial.com/v1`)
- **Standalone ZCode:** Model Settings → `AgentHub Daytona Spot` (`account:zai-start-plan` unchanged)
- **Amp:** `openai/agent-specialist` (routes via priority 1 custom-url router; priority 0 ChatGPT subscription unchanged)
- **AutoClaw:** Settings → Models & API → Add custom model (`https://inference.shtrial.com/v1`, `AGENTHUB_INFERENCE_KEY`)
- **Live-verified 2026-11-25 on `agent-turbo`:** opencode, codex, droid (Factory), grok, copilot, kilo and cline each answered through the gateway.
- **Claude Code / Cursor / Devin / Antigravity:** preserve native subscriptions; delegate to Daytona-backed hosts via AgentHub `dispatch`.

## Credentials

- `AGENTHUB_INFERENCE_KEY`: Windows User environment variable + protected copy in `%USERPROFILE%\.config\opencode\daytona\secrets\inference.key` (used for Copilot CLI / Cline / ZCode).
- `LITELLM_MASTER_KEY`: `%USERPROFILE%\.config\opencode\daytona\secrets\litellm.master` (user-only ACL) and `/opt/agenthub/inference-gateway/.env` on `sh-inference`.
- Studio owner / OIDC credentials: `%USERPROFILE%\.config\opencode\daytona\secrets\studio.owner`, `%USERPROFILE%\.config\opencode\daytona\secrets\studio.litellm.key`, and `%USERPROFILE%\.config\opencode\daytona\secrets\studio.clerk.oidc` (all user-only ACL; never committed).
