#!/bin/bash
# Serving recipe: Qwen3.8-27B-Uncensored-FP8 via vLLM ROCm (AMD MI355X CDNA4 gfx950).
# Downloads with Xet to fast local disk (/opt/models) to avoid shiftfs IO errors, then persists to /mnt/opencode-weights.
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/opencode-weights}"
MODEL_REPO="${MODEL_REPO:-orcarouter/Qwen3.8-27B-Uncensored-FP8}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3.8-27b-unc-q8}"
PORT="${PORT:-8001}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-131072}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-16384}"
MTP_TOKENS="${MTP_TOKENS:-3}"
GPU_TYPE="${GPU_TYPE:-unknown}"

PERSIST_DIR="$WEIGHTS_ROOT/specialist"
STAGE_DIR="/opt/models/specialist"
LOG_FILE="/tmp/specialist.log"
MANIFEST_DIR="$WEIGHTS_ROOT/manifests"

mkdir -p "$MANIFEST_DIR" "$PERSIST_DIR" /opt/models /run
exec >> "$LOG_FILE" 2>&1

echo "boot_vllm_rocm_gfx950 $(date -u +%Y-%m-%dT%H:%M:%SZ) port=$PORT ctx=$MAX_MODEL_LEN seqs=$MAX_NUM_SEQS util=$GPU_MEM_UTIL"
vllm --version || true
rocm-smi --showproductname || true

export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

python3 - <<PY
import json, pathlib, shutil
from huggingface_hub import model_info, snapshot_download

persist = pathlib.Path("$PERSIST_DIR")
stage = pathlib.Path("$STAGE_DIR")
manifest = pathlib.Path("$MANIFEST_DIR/specialist-runtime.txt")
token_path = pathlib.Path("/run/hf.token")
token = token_path.read_text().strip() if token_path.is_file() else ""

lines = ["backend=vllm-rocm-gfx950", "repo=$MODEL_REPO"]
try:
    import vllm
    lines.append(f"vllm={vllm.__version__}")
except Exception as exc:
    lines.append(f"vllm_error={type(exc).__name__}")
try:
    info = model_info("$MODEL_REPO", token=token or None)
    lines.append(f"revision={info.sha}")
except Exception as exc:
    lines.append(f"revision_error={type(exc).__name__}")
try:
    manifest.write_text("\n".join(lines) + "\n")
except Exception as exc:
    print(f"manifest_write_warn={type(exc).__name__}")
print("\n".join(lines))

def weights_complete(d: pathlib.Path) -> bool:
    ready = d / "ready.json"
    if ready.is_file():
        try:
            meta = json.loads(ready.read_text(encoding="utf-8"))
            files = meta.get("files") or {}
            if meta.get("repo") == "$MODEL_REPO" and files:
                return all((d / name).is_file() and (d / name).stat().st_size == size for name, size in files.items())
        except Exception:
            return False
    if not (d / "config.json").is_file():
        return False
    idx = d / "model.safetensors.index.json"
    if idx.is_file():
        data = json.loads(idx.read_text(encoding="utf-8"))
        shards = set((data.get("weight_map") or {}).values())
        return bool(shards) and all((d / s).is_file() and (d / s).stat().st_size > 0 for s in shards)
    return any(p.stat().st_size > 0 for p in d.glob("*.safetensors"))

if weights_complete(persist):
    print("staging complete weights from volume", persist, "->", stage, flush=True)
    shutil.rmtree(stage, ignore_errors=True)
    shutil.copytree(persist, stage, ignore=shutil.ignore_patterns(".cache", "ready.json"))
elif weights_complete(stage):
    print("local stage already complete", stage, flush=True)
else:
    print("downloading weights to local disk", stage, flush=True)
    stage.mkdir(parents=True, exist_ok=True)
    snapshot_download(
        "$MODEL_REPO",
        local_dir=str(stage),
        token=token or None,
    )
    print("download-complete", flush=True)
    try:
        (persist / "ready.json").unlink(missing_ok=True)
        persisted_files = {}
        items = sorted(
            [p for p in stage.iterdir() if p.name != ".cache" and p.is_file()],
            key=lambda p: (p.name == "config.json", p.name),
        )
        for item in items:
            src_size = item.stat().st_size
            dst = persist / item.name
            if not dst.is_file() or dst.stat().st_size != src_size:
                shutil.copyfile(item, dst)
            if dst.stat().st_size != src_size:
                raise RuntimeError(f"size mismatch after copy for {item.name}: {dst.stat().st_size} != {src_size}")
            persisted_files[item.name] = src_size
        (persist / "ready.json").write_text(json.dumps({"repo": "$MODEL_REPO", "files": persisted_files}) + "\n", encoding="utf-8")
        print("persisted weights to volume", persist, flush=True)
    except Exception as exc:
        print(f"persist_warn={type(exc).__name__}: {exc}", flush=True)
PY

echo "staged $(date -u +%Y-%m-%dT%H:%M:%SZ)"

export VLLM_API_KEY
VLLM_API_KEY="$(cat /run/llm.key)"

HELP_TEXT="$(vllm serve --help=all 2>&1 || vllm serve --help 2>&1 || true)"

ARGS=(
  "$STAGE_DIR"
  --served-model-name "$SERVED_MODEL_NAME"
  --host 0.0.0.0
  --port "$PORT"
  --tensor-parallel-size 1
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-model-len "$MAX_MODEL_LEN"
  --max-num-seqs "$MAX_NUM_SEQS"
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS"
  --trust-remote-code
)

grep -q -- "--enable-prefix-caching" <<<"$HELP_TEXT" && ARGS+=(--enable-prefix-caching)
grep -q -- "--enable-chunked-prefill" <<<"$HELP_TEXT" && ARGS+=(--enable-chunked-prefill)
grep -q -- "--reasoning-parser" <<<"$HELP_TEXT" && ARGS+=(--reasoning-parser qwen3)
grep -q -- "--tool-call-parser" <<<"$HELP_TEXT" && ARGS+=(--tool-call-parser qwen3_coder)
grep -q -- "--enable-auto-tool-choice" <<<"$HELP_TEXT" && ARGS+=(--enable-auto-tool-choice)

if [[ "$MTP_TOKENS" -gt 0 ]] && grep -q -- "--speculative-config" <<<"$HELP_TEXT"; then
  ARGS+=(--speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":$MTP_TOKENS}")
fi
if grep -q -- "--default-chat-template-kwargs" <<<"$HELP_TEXT"; then
  ARGS+=(--default-chat-template-kwargs '{"enable_thinking":true,"reasoning_effort":"medium"}')
fi
if grep -q -- "--reasoning-effort-map" <<<"$HELP_TEXT"; then
  ARGS+=(--reasoning-effort-map '{"high":"medium"}')
fi

OVERLAY_PREFIX="$(awk '/\/var\/lib\/docker\/overlay2\/[^/]+\/merged\//{match($0, /\/var\/lib\/docker\/overlay2\/[^/]+\/merged/); print substr($0, RSTART, RLENGTH); exit}' /proc/self/maps || true)"
if [[ -n "$OVERLAY_PREFIX" && ! -e "$OVERLAY_PREFIX" ]]; then
  mkdir -p "$(dirname "$OVERLAY_PREFIX")"
  ln -sfn / "$OVERLAY_PREFIX"
  echo "linked_sysbox_overlay=$OVERLAY_PREFIX -> /"
fi

# Restore precompiled torch.compile / vLLM caches if persisted on volume.
VLLM_VER="$(python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo unknown)"
CACHE_ARCHIVE="$WEIGHTS_ROOT/caches/vllm-${VLLM_VER}-${GPU_TYPE}.tar.gz"
if [[ -s "$CACHE_ARCHIVE" ]] && [[ ! -d /root/.cache/vllm || -z "$(ls -A /root/.cache/vllm 2>/dev/null || true)" ]]; then
  mkdir -p /root/.cache
  tar -xzf "$CACHE_ARCHIVE" -C /root/.cache && echo "restored_vllm_cache=$CACHE_ARCHIVE" || echo "warn_vllm_cache_restore_failed"
fi

exec vllm serve "${ARGS[@]}"
