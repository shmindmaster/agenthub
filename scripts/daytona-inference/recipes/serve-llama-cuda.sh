#!/bin/bash
# Serving recipe: Qwen3.8-Flash-Next-Uncensored-GGUF via llama.cpp CUDA (NVIDIA H200/B200/B300).
# Places the ~54 GB PLE n-gram embedding tensor in system RAM with --lazy-mode off.
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/opencode-weights}"
MODEL_REPO="${MODEL_REPO:-orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF}"
QUANT="${QUANT:-Q8_0}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-agent-flagship}"
PORT="${PORT:-8002}"
CTX_SIZE="${CTX_SIZE:-131072}"
PARALLEL="${PARALLEL:-1}"
BATCH_SIZE="${BATCH_SIZE:-4096}"
UBATCH_SIZE="${UBATCH_SIZE:-2048}"
CACHE_TYPE_K="${CACHE_TYPE_K:-f16}"
CACHE_TYPE_V="${CACHE_TYPE_V:-f16}"
DRAFT_GGUF="${DRAFT_GGUF:-}"
SPEC_DRAFT_MAX="${SPEC_DRAFT_MAX:-3}"

PERSIST_DIR="$WEIGHTS_ROOT/flagship-$QUANT"
STAGE_DIR="/opt/models/flagship-$QUANT"
LOG_FILE="/tmp/flagship.log"
MANIFEST_DIR="$WEIGHTS_ROOT/manifests"

mkdir -p "$MANIFEST_DIR" "$PERSIST_DIR" /opt/models /run
exec >> "$LOG_FILE" 2>&1

echo "boot_llama_cuda $(date -u +%Y-%m-%dT%H:%M:%SZ) quant=$QUANT port=$PORT ctx=$CTX_SIZE parallel=$PARALLEL"
nvidia-smi -L || true
LLAMA_BIN="${LLAMA_BIN:-$(command -v llama-server || echo /opt/llama.cpp/build/bin/llama-server)}"
"$LLAMA_BIN" --version || true

export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

python3 - <<PY
import pathlib, shutil
from huggingface_hub import model_info, snapshot_download

persist = pathlib.Path("$PERSIST_DIR")
stage = pathlib.Path("$STAGE_DIR")
manifest = pathlib.Path("$MANIFEST_DIR/flagship-${QUANT}-runtime.txt")
token_path = pathlib.Path("/run/hf.token")
token = token_path.read_text().strip() if token_path.is_file() else ""

lines = ["backend=llama-cuda", "repo=$MODEL_REPO", "quant=$QUANT"]
try:
    info = model_info("$MODEL_REPO", token=token or None)
    lines.append(f"revision={info.sha}")
except Exception as exc:
    lines.append(f"revision_error={type(exc).__name__}")
try:
    manifest.write_text("\n".join(lines) + "\n")
except Exception as exc:
    print(f"manifest_write_warn={type(exc).__name__}")

existing_vol = sorted(persist.rglob("*.gguf"))
existing_stage = sorted(stage.rglob("*.gguf")) if stage.exists() else []
if existing_vol:
    shutil.rmtree(stage, ignore_errors=True)
    shutil.copytree(persist, stage, ignore=shutil.ignore_patterns(".cache"))
elif not existing_stage:
    stage.mkdir(parents=True, exist_ok=True)
    patterns = [f"*{ '$QUANT' }*.gguf", f"*{ '$QUANT'.lower() }*.gguf", "*mmproj*.gguf"]
    snapshot_download(
        "$MODEL_REPO",
        local_dir=str(stage),
        allow_patterns=patterns,
        token=token or None,
    )
    print("download-complete")
    try:
        for item in stage.rglob("*.gguf"):
            rel = item.relative_to(stage)
            dst = persist / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.is_file() or dst.stat().st_size != item.stat().st_size:
                shutil.copyfile(item, dst)
    except Exception as exc:
        print(f"persist_warn={type(exc).__name__}: {exc}")
PY

FIRST_SHARD="$(find "$STAGE_DIR" -type f -name '*.gguf' ! -name '*mmproj*' ! -name '*draft*' | sort | head -n 1)"
if [[ -z "$FIRST_SHARD" ]]; then
  echo "NO_GGUF_SHARD_FOUND in $STAGE_DIR"
  exit 4
fi
echo "first_shard=$FIRST_SHARD"

export LLAMA_API_KEY
LLAMA_API_KEY="$(cat /run/llm.key)"

ARGS=(
  --model "$FIRST_SHARD"
  --alias "$SERVED_MODEL_NAME"
  --host 0.0.0.0
  --port "$PORT"
  --n-gpu-layers 999
  --ctx-size "$CTX_SIZE"
  --parallel "$PARALLEL"
  --lazy-mode off
  --override-tensor 'per_layer_token_embd.weight=CPU'
  --flash-attn on
  --batch-size "$BATCH_SIZE"
  --ubatch-size "$UBATCH_SIZE"
  --cache-prompt
  --cache-type-k "$CACHE_TYPE_K"
  --cache-type-v "$CACHE_TYPE_V"
  --reasoning on
  --reasoning-effort medium
  --jinja
  --temp 1.0
  --top-p 0.95
  --top-k 20
  --min-p 0
  --metrics
)

if [[ -n "$DRAFT_GGUF" && -f "$DRAFT_GGUF" ]]; then
  ARGS+=(-md "$DRAFT_GGUF" --spec-type draft-mtp --spec-draft-n-max "$SPEC_DRAFT_MAX")
fi

exec "$LLAMA_BIN" "${ARGS[@]}"
