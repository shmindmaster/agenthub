# Daytona Spot Inference Gateway (NVIDIA + AMD)

Permanent inference gateway and unified NVIDIA/AMD Daytona spot GPU operations for AgentHub coding agents.

## Architecture

- **Permanent HTTPS Endpoint:** `https://inference.shtrial.com/v1` (and Media Lab: `https://inference.shtrial.com/v1/media`)
  - DNS `A` record for `inference.shtrial.com` is hosted in DigitalOcean DNS (`shtrial.com`).
  - Reverse-proxied through Caddy on `sh-forge` (`129.212.152.9`), preserving `/v1/chat/completions`, `/v1/responses`, `/v1/models`, and `/health/liveliness` on LiteLLM (`127.0.0.1:4000`, gated by Bearer auth), proxying `handle_path /v1/media/*` to Slot 2 `:8189` (gated by owner IP `<OWNER_IP>` or `AGENTHUB_INFERENCE_KEY` Bearer token, injecting `x-daytona-preview-token` and the media gateway token), and restricting admin endpoints (`/ui`, `/model/*`, `/key/*`) to `<OWNER_IP>`.
  - Backed by LiteLLM + PostgreSQL (`scripts/daytona-inference/gateway/`), preserving model aliases without ever rewriting coding-agent configs or DNS on spot eviction.
  - Pre-`2026-12-01` migration off `sh-forge`: see [MIGRATION-2026-12-01.md](../../scripts/daytona-inference/gateway/MIGRATION-2026-12-01.md).
- **Dual-MI355X Spot Architecture (2/2 Max GPU Slots):**
  - **Slot 1 (`engineering` role, `agenthub-engineering`):** Single MI355X (288 GB CDNA4 `gfx950`) running both vLLM ROCm (`:8001`, `Qwen3.8-27B-Uncensored-FP8`, 262144 context) and `llama-server` HIP (`:8002`, `Qwen3.8-Flash-Next-Uncensored-GGUF` `Q8_0`, 262144 context, CPU PLE) on `opencode-agent-weights` (`/mnt/opencode-weights`), serving `agent-specialist`, `agent-fast`, `agent-vision`, `agent-flagship`, and (after `retire-legacy-turbo`) `agent-turbo`.
  - **Slot 2 (`media` role, `agenthub-media`):** Single MI355X (288 GB) on `agenthub-media-weights` (`/mnt/media-weights`), running ComfyUI (`127.0.0.2:8188`) + Media Gateway (`:8189`, `/healthz` & `/v1/info`) behind `https://inference.shtrial.com/v1/media/*` (`<MEDIA_PREVIEW_URL>` upstream).
- **Permanent Model Aliases (`registry/inference-providers.json`):**
  - `agent-fast`: 27B FP8 routine/exploration (`low` default reasoning, 262144 ctx / 32768 output)
  - `agent-specialist`: 27B FP8 general engineering + vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-vision`: 27B FP8 browser/desktop/media vision (`medium` default reasoning, 262144 ctx / 32768 output)
  - `agent-turbo`: Flash-Next (`medium` default reasoning, 262144 ctx / 32768 output; legacy H200 `qwen38-turbo-q6k` until `retire-legacy-turbo` moves it to Slot 1 `:8002`)
  - `agent-flagship`: Flash-Next Q8_0 flagship reasoning (`medium` default reasoning, 262144 ctx / 32768 output; `Q8_0` on MI355X/B300/B200, explicit `--allow-q6-fallback` on H200)
- **Hard Operating Constraints:**
  - Maximum **2** GPU instances combined across NVIDIA and AMD, **1** GPU per instance.
  - **Spot-only** (`spot=True`); never falls back to on-demand.
  - Protected live sandbox `qwen38-turbo-q6k` and protected volume `llm-models` are never touched by `up`/`down`/`extend`/`save-cache`; `retire-legacy-turbo` refuses unless `agenthub-engineering` is `STARTED` and both `agent-specialist` and `agent-flagship` pass live verification on `https://inference.shtrial.com/v1`.
  - No silent fallback to paid providers or different checkpoints on unavailable aliases.

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
python $gpu extend engineering 120         # extend wall-clock TTL
python $gpu reconcile                      # prune evicted backends & re-sync live turbo
python $gpu down media                     # delete managed sandbox
python $gpu save-cache specialist          # persist /root/.cache/{vllm,flashinfer} to opencode-agent-weights
```

Set `SH_FORGE_UPDATE=1` when running `gpu.py up media` to update `/opt/forge/caddy/Caddyfile` automatically using the template in `scripts/daytona-inference/gateway/Caddyfile.snippet` (`<OWNER_IP>`, `<MEDIA_PREVIEW_URL>`, `<AGENTHUB_INFERENCE_KEY>`, `<MEDIA_PREVIEW_TOKEN>`, `<MEDIA_GATEWAY_TOKEN>` placeholders are never stored in git-tracked files).

## Persisted Daytona Fast-Boot Assets

To minimize Spot recovery startup time (avoiding cold container image pulls, 29 GB Hugging Face weight downloads, and ~4.5 minutes of `torch.compile` + DeepGEMM SM90a kernel compilation):

- **Weights & JIT Cache Volume (`opencode-agent-weights`, mounted at `/mnt/opencode-weights`):**
  - `/mnt/opencode-weights/specialist/`: verified `orcarouter/Qwen3.8-27B-Uncensored-FP8` weights (`config.json` + 7 shards).
  - `/mnt/opencode-weights/caches/vllm-0.24.0-H200.tar.gz` (+ `.sha256`): persisted `/root/.cache/vllm` and `/root/.cache/flashinfer` compiled kernels, restored automatically by `recipes/serve-vllm-cuda.sh` before `exec vllm serve`.
- **Reusable `ACTIVE` Daytona GPU Snapshots (in ABACare AI LLC org):**
  - `agenthub-vllm-cuda-0-24-0-h200` (`vllm/vllm-openai:v0.24.0` + `huggingface_hub` + `hf_xet`, entrypoint `sleep infinity`)
  - `agenthub-llama-cuda-h200` (`ghcr.io/ggml-org/llama.cpp:server-cuda` + `python3` + `hf_xet`, entrypoint `sleep infinity`)
  - `gpu.py up` checks `resolve_active_snapshot()` first and boots directly via `CreateSandboxFromSnapshotParams`, falling back automatically to `CreateSandboxFromImageParams` for GPUs/backends without an active snapshot (such as AMD `MI355X`).

## What Changes Next Time (Zero-DNS Spot Recovery vs. Gateway Migration)

- **Spot GPU eviction or expiry:** Requires **zero DNS updates** and **zero coding-agent configuration changes**. Run `python $gpu up specialist --gpu auto` (or `recover specialist`), which boots from snapshot/persisted weights/JIT cache and updates LiteLLM's PostgreSQL route table behind `https://inference.shtrial.com/v1`.
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
