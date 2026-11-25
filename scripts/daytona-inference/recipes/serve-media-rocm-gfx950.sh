#!/bin/bash
# Serving recipe: Slot 2 Media Lab on AMD MI355X (288 GB CDNA4 gfx950).
# Hosts both research-uncensored (Qwen-Image-2.1 Omni, LTX-2.5 uncensored, LFM3-Omni-2B-heretic)
# and commercial-authorized (Qwen-Image-2512, Z-Image-Turbo, Wan 2.2, ACE-Step 1.5, ZONOS3-Mini,
# Qwen3-TTS, SOV-Transcribe-1, Whisper) from local disk; the Daytona volume
# keeps a copy. The volume is an S3 mount: it cannot rename or rewrite a file, so nothing downloads onto it.
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/media-weights}"
PORT="${PORT:-8189}"
GG="/opt/gpu-gen"
PY="$GG/venv/bin/python"
LOG_FILE="/tmp/media.log"

mkdir -p "$WEIGHTS_ROOT/weights" "$GG"/{weights,caches/inductor,caches/triton,hf-cache,server,logs,out,comfy-out} /run
exec >> "$LOG_FILE" 2>&1

echo "boot_media_rocm $(date -u +%Y-%m-%dT%H:%M:%SZ) port=$PORT"
rocm-smi --showproductname --showmeminfo vram || true

# Bootstrap ComfyUI v0.46.0 + venv when booting directly from the base ROCm/CUDA image (without custom snapshot).
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v sox >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y --no-install-recommends \
    git ffmpeg sox libsox-fmt-all libsndfile1 libsndfile1-dev ca-certificates curl gcc g++ procps
fi

if [[ ! -d "$GG/ComfyUI/.git" && ! -f "$GG/ComfyUI/main.py" ]]; then
  echo "bootstrapping ComfyUI v0.46.0 -> $GG/ComfyUI"
  rm -rf "$GG/ComfyUI"
  git clone --depth 1 --branch "v0.46.0" https://github.com/Comfy-Org/ComfyUI.git "$GG/ComfyUI"
fi
if [[ ! -d "$GG/ComfyUI/custom_nodes/ComfyUI-GGUF" ]]; then
  mkdir -p "$GG/ComfyUI/custom_nodes"
  git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git "$GG/ComfyUI/custom_nodes/ComfyUI-GGUF"
fi

if [[ ! -x "$PY" ]] || ! "$PY" -c "import aiohttp, huggingface_hub, hf_xet, transformers, soundfile" >/dev/null 2>&1; then
  echo "bootstrapping Python venv -> $GG/venv"
  if [[ ! -x "$PY" ]]; then
    python3 -m venv --system-site-packages "$GG/venv"
  fi
  TORCH_VER="$(python3 -c 'import torch; print(torch.__version__.split("+")[0])')"
  printf "torch==%s\n" "$TORCH_VER" > /tmp/torch-pin.txt
  grep -vE '^(torch|torchvision|torchaudio)([=<>~! ]|$)' "$GG/ComfyUI/requirements.txt" > /tmp/comfy-reqs.txt
  "$PY" -m pip install --no-cache-dir -c /tmp/torch-pin.txt -r /tmp/comfy-reqs.txt
  "$PY" -m pip install --no-cache-dir -c /tmp/torch-pin.txt \
    "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0" aiohttp soundfile librosa \
    "transformers>=4.50.0" accelerate peft gguf safetensors einops sentencepiece
  "$PY" -m pip install --no-cache-dir --no-deps "qwen-tts==0.1.1" || true
  "$PY" -m pip install --no-cache-dir -c /tmp/torch-pin.txt "git+https://github.com/Zyphra/ZONOS3-Mini.git" || true
  rm -f /tmp/torch-pin.txt /tmp/comfy-reqs.txt
fi

"$PY" -c "import torch; print('torch:', torch.__version__, 'hip:', getattr(torch.version, 'hip', None), 'avail:', torch.cuda.is_available(), 'dev:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)" || true

export HF_HOME="$GG/hf-cache"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"
export TORCHINDUCTOR_CACHE_DIR="$GG/caches/inductor"
export TRITON_CACHE_DIR="$GG/caches/triton"
export GG="$GG"
export GG_WEIGHTS="$GG/weights"
export GG_PERSIST="$WEIGHTS_ROOT/weights"
export GG_OUT="$GG/out"
export GG_BACKEND="rocm"
export GG_VRAM_TOTAL_GB="288"

# Ensure bearer token for gateway (uses worker key if provisioned so gateway proxy can pass static secret)
if [[ -s /run/llm.key ]]; then
  cp /run/llm.key "$GG/token"
  chmod 600 "$GG/token"
elif [[ ! -s "$GG/token" ]]; then
  umask 077; head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$GG/token"
  chmod 600 "$GG/token"
fi

# Fetch every pinned file to local disk (from the volume when it holds the same revision), then link it into ComfyUI.
"$PY" - <<'PY'
import json, os, pathlib, shutil
from concurrent.futures import ThreadPoolExecutor
from huggingface_hub import get_hf_file_metadata, hf_hub_download, hf_hub_url, snapshot_download

W = pathlib.Path(os.environ["GG_WEIGHTS"])
V = pathlib.Path(os.environ["GG_PERSIST"])
COMFY = pathlib.Path("/opt/gpu-gen/ComfyUI/models")
tok = pathlib.Path("/run/hf.token").read_text().strip() if pathlib.Path("/run/hf.token").is_file() else ""

# Tuple: (repo, rev, remote_file_or_empty, comfy_subdir, local_link_name)
SPECS = [
    # --- Research / Uncensored Aug-Nov 2026 ---
    ("chatrlabs/Qwen-Image-2.1-Uncensored-Omni-Quantized", "af0343c25951", "qwen-image-2.1-step90000-BF16/diffusion_pytorch_model.safetensors", "diffusion_models", "chatrlabs_qwen_image21_step90000_bf16.safetensors"),
    ("chatrlabs/Qwen-Image-2.1-Uncensored-Omni-Quantized", "af0343c25951", "qwen-image-2.1-step90000-FP8-comfy.safetensors", "diffusion_models", "chatrlabs_qwen_image21_step90000_fp8.safetensors"),
    ("chatrlabs/Qwen-Image-2.1-Uncensored-Omni-LoRA-v0.1", "04651bc83877", "chatrlabs-omni-turbo-8step-fp32.safetensors", "loras", "chatrlabs-omni-turbo-8step-fp32.safetensors"),
    ("Comfy-Org/Qwen-Image-2.1", "aacf31a6d48e", "text_encoders/qwen3vl_8b_bf16.safetensors", "text_encoders", "qwen3vl_8b_bf16.safetensors"),
    ("Comfy-Org/Qwen-Image-2.1", "aacf31a6d48e", "vae/qwen_image_2.1_vae_bf16.safetensors", "vae", "qwen_image_2.1_vae_bf16.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/diffusion_models/ltx25_uncensored_v1.1-fp8_scaled.safetensors", "diffusion_models", "ltx25_uncensored_v1.1-fp8_scaled.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/text_encoders/gemma4_12b_ltx25_uncensored-int8.safetensors", "text_encoders", "gemma4_12b_ltx25_uncensored-int8.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/vae/ltx25_uncensored_video_vae.safetensors", "vae", "ltx25_uncensored_video_vae.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/vae/ltx25_uncensored_audio_vae.safetensors", "vae", "ltx25_uncensored_audio_vae.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors", "latent_upscale_models", "ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"),
    ("ChrisColeTech/LTX-2.5-uncensored-v1.1-FP8", "592aaa11f13a", "split/latent_upscale_models/ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors", "latent_upscale_models", "ltx-2.5-latent-temporal-upscaler-x2-bf16-1.0.safetensors"),
    ("rodrigomt/LFM3-Omni-2B-heretic", "ecd80dae8705", "", "", ""),
    # --- Commercial-Authorized (Apache-2.0 / MIT) ---
    ("Comfy-Org/Qwen-Image_ComfyUI", "1f12b17be14c", "split_files/diffusion_models/qwen_image_2512_bf16.safetensors", "diffusion_models", "qwen_image_2512_bf16.safetensors"),
    ("Comfy-Org/Qwen-Image_ComfyUI", "1f12b17be14c", "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors", "text_encoders", "qwen_2.5_vl_7b_fp8_scaled.safetensors"),
    ("Comfy-Org/Qwen-Image_ComfyUI", "1f12b17be14c", "split_files/vae/qwen_image_vae.safetensors", "vae", "qwen_image_vae.safetensors"),
    ("Comfy-Org/Z-Image-Turbo", "6fc90a3b1b65", "split_files/diffusion_models/z_image_turbo_bf16.safetensors", "diffusion_models", "z_image_turbo_bf16.safetensors"),
    ("Comfy-Org/Z-Image-Turbo", "6fc90a3b1b65", "split_files/text_encoders/qwen_3_4b.safetensors", "text_encoders", "qwen_3_4b.safetensors"),
    ("Comfy-Org/Z-Image-Turbo", "6fc90a3b1b65", "split_files/vae/ae.safetensors", "vae", "ae.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors", "diffusion_models", "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors", "diffusion_models", "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/diffusion_models/wan2.2_s2v_14B_fp8_scaled.safetensors", "diffusion_models", "wan2.2_s2v_14B_fp8_scaled.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors", "text_encoders", "umt5_xxl_fp8_e4m3fn_scaled.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/vae/wan_2.1_vae.safetensors", "vae", "wan_2.1_vae.safetensors"),
    ("Comfy-Org/Wan_2.2_ComfyUI_Repackaged", "ee6f4a40737a", "split_files/audio_encoders/wav2vec2_large_english_fp16.safetensors", "audio_encoders", "wav2vec2_large_english_fp16.safetensors"),
    ("Comfy-Org/ACE-Step-1.5", "371bb1680f8c", "checkpoints/ace_step_1.5_turbo_aio.safetensors", "checkpoints", "ace_step_1.5_turbo_aio.safetensors"),
    ("Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice", "0c0e3051f131", "", "", ""),
    ("openai/whisper-large-v3-turbo", "41f01f3fe87f", "", "", ""),
    ("Zyphra/ZONOS3-Mini", "2921b8821772", "", "", ""),
    ("salesforce-sovereign-intelligence/SOV-Transcribe-1", "505d8fae2439", "", "", ""),
]

def from_volume(repo: str, rev: str, rel: str) -> bool:
    # ready-<rev>.json is written last, so a file it lists was copied in full.
    ready = V / repo / f"ready-{rev}.json"
    if not ready.is_file():
        return False
    want = json.loads(ready.read_text())
    names = [rel] if rel else list(want)
    if not all(n in want and (V / repo / n).is_file() and (V / repo / n).stat().st_size == want[n] for n in names):
        return False
    for n in names:
        dst = W / repo / n
        if not (dst.is_file() and dst.stat().st_size == want[n]):
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(V / repo / n, dst)
    return True

def fetch(spec) -> None:
    repo, rev, rel, cdir, cname = spec
    dest = W / repo
    dest.mkdir(parents=True, exist_ok=True)
    if from_volume(repo, rev, rel):
        print(f"volume {repo}/{rel}", flush=True)
    elif rel:
        size = get_hf_file_metadata(hf_hub_url(repo, rel, revision=rev), token=tok or None).size or 0
        target = dest / rel
        if not (target.is_file() and target.stat().st_size == size):
            print(f"downloading {repo}/{rel} ({size/1e9:.2f} GB)", flush=True)
            hf_hub_download(repo, rel, local_dir=str(dest), revision=rev, token=tok or None)
        if size and target.stat().st_size != size:
            raise RuntimeError(f"size mismatch {repo}/{rel}: {target.stat().st_size} != {size}")
    else:
        print(f"snapshot_download {repo}@{rev}", flush=True)
        ignore = ["*.bin", "*.msgpack", "*.h5", "*.ot"]
        if repo == "Zyphra/ZONOS3-Mini":
            ignore += ["web/*", "gguf/*.gguf", "gguf/edit/*", "autoencoder/heads/full_mr/*"]
        snapshot_download(repo, local_dir=str(dest), revision=rev, ignore_patterns=ignore, token=tok or None)
    if cdir:
        link = COMFY / cdir / cname
        link.parent.mkdir(parents=True, exist_ok=True)
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(dest / rel)

with ThreadPoolExecutor(6) as pool:
    list(pool.map(fetch, SPECS))
(W / "specs.json").write_text(json.dumps([[s[0], s[1], s[2]] for s in SPECS]))
print("ALL_MEDIA_WEIGHTS_VERIFIED", flush=True)
PY

# Launch ComfyUI on loopback alias 127.0.0.2:8188 (warm residency on 288 GB GPU) and Gateway on 0.0.0.0:$PORT
cd "$GG/ComfyUI"
COMFY_HELP="$("$PY" main.py --help 2>&1 || true)"
COMFY_ARGS=(main.py --listen 127.0.0.2 --port 8188 --highvram --output-directory "$GG/comfy-out" --disable-auto-launch)
grep -q -- "--cache-lru" <<<"$COMFY_HELP" && COMFY_ARGS+=(--cache-lru 8)
"$PY" "${COMFY_ARGS[@]}" > "$GG/logs/comfyui.log" 2>&1 &
COMFY_PID=$!

for i in $(seq 1 90); do
  if ! kill -0 "$COMFY_PID" 2>/dev/null; then
    echo "COMFY_EXITED_EARLY"
    tail -n 50 "$GG/logs/comfyui.log" || true
    exit 1
  fi
  if curl -sf http://127.0.0.2:8188/system_stats >/dev/null 2>&1; then
    echo "comfyui_ready after $((i*2))s"
    break
  fi
  sleep 2
done

# Copy anything new to the volume while serving, so the next box starts from it.
"$PY" - > "$GG/logs/persist.log" 2>&1 <<'PY' &
import json, os, pathlib, shutil
W, V = pathlib.Path(os.environ["GG_WEIGHTS"]), pathlib.Path(os.environ["GG_PERSIST"])
repos = {}
for repo, rev, rel in json.loads((W / "specs.json").read_text()):
    repos.setdefault((repo, rev), []).append(rel)
for (repo, rev), rels in repos.items():
    src = W / repo
    files = [src / r for r in rels] if all(rels) else [p for p in src.rglob("*") if p.is_file() and ".cache" not in p.parts]
    ready = V / repo / f"ready-{rev}.json"
    want = {p.relative_to(src).as_posix(): p.stat().st_size for p in files}
    if ready.is_file() and json.loads(ready.read_text()) == want:
        continue
    for name, size in want.items():
        dst = V / repo / name
        if dst.is_file() and dst.stat().st_size == size:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists():
            dst.unlink()
        shutil.copyfile(src / name, dst)
        if dst.stat().st_size != size:
            raise RuntimeError(f"size mismatch on volume {repo}/{name}")
    if ready.exists():
        ready.unlink()
    ready.write_text(json.dumps(want))
    print("persisted", repo, rev, len(want), flush=True)
print("PERSIST_DONE", flush=True)
PY

cd "$GG"
"$PY" "$GG/server/gateway.py" > "$GG/logs/gateway.log" 2>&1 &
GW_PID=$!

wait -n "$COMFY_PID" "$GW_PID"
RC=$?
echo "media_child_exited rc=$RC"
kill "$COMFY_PID" "$GW_PID" 2>/dev/null || true
exit "$RC"
