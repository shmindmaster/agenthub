# Daytona Spot Inference Gateway (NVIDIA + AMD)

Permanent inference gateway and unified NVIDIA/AMD Daytona spot GPU operations for AgentHub coding agents.

## Architecture

- **Permanent HTTPS Endpoint:** `https://inference.shtrial.com/v1` (and Media Lab: `https://inference.shtrial.com/v1/media`)
  - DNS `A` record for `inference.shtrial.com` is hosted in DigitalOcean DNS (`shtrial.com`).
  - Reverse-proxied through Caddy on `sh-forge` (`129.212.152.9`), preserving `/v1/chat/completions`, `/v1/responses`, `/v1/models`, and `/health/liveliness` on LiteLLM (`127.0.0.1:4000`, gated by Bearer auth), proxying `handle_path /v1/media/*` to Slot 2 `:8189` (gated by owner IP `<OWNER_IP>` or `AGENTHUB_INFERENCE_KEY` Bearer token, injecting `x-daytona-preview-token` and the media gateway token), and restricting admin endpoints (`/ui`, `/model/*`, `/key/*`) to `<OWNER_IP>`.
  - Backed by LiteLLM + PostgreSQL (`scripts/daytona-inference/gateway/`), preserving model aliases without ever rewriting coding-agent configs or DNS on spot eviction.
  - Pre-`2026-12-01` migration off `sh-forge`: see [MIGRATION-2026-12-01.md](../../scripts/daytona-inference/gateway/MIGRATION-2026-12-01.md).
- **Dual-MI355X Spot Architecture (2/2 Max GPU Slots):**
  - **Slot 1 (`engineering` role, `agenthub-engineering`):** Single MI355X (288 GB CDNA4 `gfx950`) running both vLLM ROCm (`:8001`, `Qwen3.8-27B-Uncensored-FP8`, 262144 context, `gpu-memory-utilization` 0.40) and `llama-server` HIP (`:8002`, `Qwen3.8-Flash-Next-Uncensored-GGUF` `Q8_0`, two slots of 262144 context each, CPU PLE, 16 threads, restarted on its own if it crashes while the 27B keeps serving) on `opencode-agent-weights` (`/mnt/opencode-weights`), serving `agent-specialist`, `agent-fast`, `agent-vision`, `agent-flagship`, and (after `retire-legacy-turbo`) `agent-turbo`.
    - **Live-verified 2026-11-25 through `https://inference.shtrial.com/v1`** (operator run): all five aliases answered code and tool-call requests, vision worked, and a 112k-token recall test passed. Measured throughput: flagship 65-79 tok/s, 27B about 170 tok/s. VRAM in use was 279.6 of 308.9 GB as `rocm-smi` reports it (288 GiB).
  - **Slot 2 (`media` role, `agenthub-media`):** Single MI355X (288 GB) on `agenthub-media-weights` (`/mnt/media-weights`), running ComfyUI (`127.0.0.2:8188`) + Media Gateway (`:8189`, `/healthz` & `/v1/info`) behind `https://inference.shtrial.com/v1/media/*` (`<MEDIA_PREVIEW_URL>` upstream). **Not yet live-verified:** no media job has been run end to end through the gateway, the gateway and worker sources (`gateway.py`, `audio_worker.py`, `models.json`) live outside this repository in `MEDIA_STUDIO_ROOT\gpu-gen\server`, and the client only sends `authorization_profile`; the server must enforce it.
- **Permanent Model Aliases (`registry/inference-providers.json`):**
  - `agent-fast`: 27B FP8 routine/exploration (`low` default reasoning, 262144 ctx / 32768 output)
  - `agent-specialist`: 27B FP8 general engineering + vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-vision`: 27B FP8 browser/desktop/media vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-turbo`: Flash-Next (`medium` default reasoning, 262144 ctx / 32768 output; legacy H200 `qwen38-turbo-q6k` until `retire-legacy-turbo` moves it to Slot 1 `:8002`)
  - `agent-flagship`: Flash-Next Q8_0 flagship reasoning (`medium` default reasoning, 262144 ctx / 32768 output; `Q8_0` on MI355X/B300/B200, explicit `--allow-q6-fallback` on H200)
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

## GPU Lifecycle Commands

Run from Windows with `DAYTONA_API_KEY` set:

```powershell
$gpu = "$env:USERPROFILE\.config\opencode\daytona\gpu.py"
python $gpu capacity                       # live NVIDIA + AMD spot inventory
python $gpu status                         # active GPUs (N/2) + gateway aliases
python $gpu doctor                         # credentials, volumes, protected box, gateway health
python $gpu up engineering --gpu MI355X    # Slot 1 dual vLLM (:8001) + llama-server (:8002)
python $gpu retire-legacy-turbo            # gated cutover once Slot 1 is live-verified
python $gpu up media --gpu MI355X          # Slot 2 media lab (:8189) on agenthub-media-weights
python $gpu caddy-media                    # update sh-forge Caddy /v1/media/* upstream
python $gpu up specialist --gpu auto       # legacy single-slot Qwen 27B FP8
python $gpu up flagship --gpu auto         # legacy single-slot Flash-Next Q8_0
python $gpu up flagship --gpu H200 --allow-q6-fallback
python $gpu extend engineering 120         # reset wall-clock TTL (1-480 minutes)
python $gpu reconcile                      # prune evicted backends & re-sync live turbo
python $gpu down media                     # delete managed sandbox
python $gpu save-cache specialist          # persist /root/.cache/{vllm,flashinfer} to opencode-agent-weights
```

Set `SH_FORGE_UPDATE=1` when running `gpu.py up media` (or run `gpu.py caddy-media`, `--dry-run` first) to rewrite the `inference.shtrial.com` block of `/opt/forge/caddy/Caddyfile` from the template in `scripts/daytona-inference/gateway/Caddyfile.snippet`. The `<OWNER_IP>`, `<MEDIA_PREVIEW_URL>`, `<AGENTHUB_INFERENCE_KEY>`, `<MEDIA_PREVIEW_TOKEN>` and `<MEDIA_GATEWAY_TOKEN>` placeholders are filled at run time and never stored in git-tracked files; the rendered keys do sit in the Caddyfile on `sh-forge`. The whole site block is replaced, so any hand-added directive in it is lost. If `caddy validate` or the reload fails, the previous Caddyfile is written back without a reload.

`/v1/media/*` is open to the owner IP or to a request carrying `Authorization: Bearer <AGENTHUB_INFERENCE_KEY>`, which is the same key every coding agent holds; anyone with that key can queue media jobs on the GPU.

## Boot Path and Persisted Assets

- **Boxes boot from stock registry images, not custom snapshots.** Daytona cannot build a custom snapshot over 20 GB, so the AMD roles use `rocm/vllm` (engineering) and `rocm/pytorch` (media) and the recipes install what is missing at boot: `llama-server` is built once for `gfx950` and cached as a tarball under `/mnt/opencode-weights/bin/`, and ComfyUI plus its Python environment are bootstrapped on the media box. Only the H200 CUDA roles have snapshots, listed below. `catalog.json` carries no Dockerfile for the engineering or media images because none is built.
- **Weights are staged to local disk first, in parallel.** On the first boot a model downloads from Hugging Face to local disk (`/opt/models/...` for engineering, `/opt/gpu-gen/weights` for media, symlinked into ComfyUI), then a copy is written to the S3-backed volume (`/mnt/media-weights/weights`; the media recipe lists which files each pinned revision holds in `ready-<rev>.json`). On later boots the files are copied from the volume to local disk, 8 at a time, skipping any file whose size already matches, so an interrupted boot resumes. A volume copy is only trusted when its `ready.json` size manifest matches; a failed copy to the volume is a warning, and the next boot downloads again.
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
- **Claude Code / Cursor / Devin / Antigravity:** preserve native subscriptions; delegate to Daytona-backed hosts via AgentHub `dispatch`.

## Credentials

- `AGENTHUB_INFERENCE_KEY`: Windows User environment variable + protected copy in `%USERPROFILE%\.config\opencode\daytona\secrets\inference.key` (used for Copilot CLI / Cline / ZCode).
- `LITELLM_MASTER_KEY`: `%USERPROFILE%\.config\opencode\daytona\secrets\litellm.master` (user-only ACL) and `/opt/forge/inference-gateway/.env` on `sh-forge`.
