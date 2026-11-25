# Daytona Spot Inference Gateway (NVIDIA + AMD)

Permanent inference gateway and unified NVIDIA/AMD Daytona spot GPU operations for AgentHub coding agents.

## Architecture

- **Permanent HTTPS Endpoint:** `https://inference.shtrial.com/v1`
  - DNS `A` record for `inference.shtrial.com` is hosted in DigitalOcean DNS (`shtrial.com`).
  - Reverse-proxied through Caddy on `sh-forge` (`129.212.152.9`), allowing `/v1/*` and `/health/liveliness` globally (gated by LiteLLM Bearer auth) and restricting admin endpoints (`/ui`, `/model/*`, `/key/*`) to the owner IP.
  - Backed by LiteLLM + PostgreSQL (`scripts/daytona-inference/gateway/`), preserving model aliases without ever rewriting coding-agent configs or DNS on spot eviction.
  - Pre-`2026-12-01` migration off `sh-forge`: see [MIGRATION-2026-12-01.md](../../scripts/daytona-inference/gateway/MIGRATION-2026-12-01.md).
- **Permanent Model Aliases (`registry/inference-providers.json`):**
  - `agent-fast`: 27B FP8 routine/exploration (`low` default reasoning)
  - `agent-specialist`: 27B FP8 general engineering + vision (`medium` default reasoning)
  - `agent-vision`: 27B FP8 browser/desktop/media vision (`medium` default reasoning)
  - `agent-turbo`: Flash-Next Q6_K (`medium` default reasoning; currently backed by protected live H200 `qwen38-turbo-q6k`)
  - `agent-flagship`: Flash-Next Q8_0 flagship reasoning (`medium` default reasoning; `Q8_0` on MI355X/B300/B200, explicit `--allow-q6-fallback` on H200)
- **Hard Operating Constraints:**
  - Maximum **2** GPU instances combined across NVIDIA and AMD, **1** GPU per instance.
  - **Spot-only** (`spot=True`); never falls back to on-demand.
  - Protected live sandbox `qwen38-turbo-q6k` and protected volume `llm-models` are never touched; managed weights persist on `opencode-agent-weights`.
  - No silent fallback to paid providers or different checkpoints on unavailable aliases.

## GPU Lifecycle Commands

Run from Windows with `DAYTONA_API_KEY` set:

```powershell
$gpu = "$env:USERPROFILE\.config\opencode\daytona\gpu.py"
python $gpu capacity                       # live NVIDIA + AMD spot inventory
python $gpu status                         # active GPUs (N/2) + gateway aliases
python $gpu doctor                         # credentials, volume, protected box, gateway health
python $gpu up specialist --gpu auto       # launch Qwen 27B FP8 (H200/MI355X/B200/B300/RTX-PRO-6000/H100)
python $gpu up flagship --gpu auto         # launch Flash-Next Q8_0 (MI355X/B300/B200)
python $gpu up flagship --gpu H200 --allow-q6-fallback
python $gpu extend specialist 120          # extend wall-clock TTL
python $gpu reconcile                      # prune evicted backends & re-sync live turbo
python $gpu down specialist                # delete managed sandbox & deregister aliases
python $gpu save-cache specialist          # persist /root/.cache/{vllm,flashinfer} to opencode-agent-weights
```

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
