#!/bin/bash
# Serving recipe: Dual-model Engineering Slot 1 on AMD MI355X (288 GB CDNA4 gfx950).
# Runs BOTH:
#   1) Qwen3.8-27B-Uncensored-FP8 via vLLM ROCm (:8001, 262144 ctx, MTP=3, AITER, prefix caching)
#   2) Qwen3.8-Flash-Next-Uncensored-GGUF Q8_0 via llama-server HIP (:8002, 262144 ctx, CPU PLE)
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/opencode-weights}"
SPEC_REPO="${SPEC_REPO:-orcarouter/Qwen3.8-27B-Uncensored-FP8}"
FLAG_REPO="${FLAG_REPO:-orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF}"
FLAG_QUANT="${FLAG_QUANT:-Q8_0}"

SPEC_PORT="${SPEC_PORT:-8001}"
FLAG_PORT="${FLAG_PORT:-8002}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-262144}"
CTX_SIZE="${CTX_SIZE:-262144}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.40}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-16384}"
MTP_TOKENS="${MTP_TOKENS:-3}"
PARALLEL="${PARALLEL:-2}"
THREADS="${THREADS:-16}"  # the box has 16 vCPUs, but llama-server counts the host's 192
BATCH_SIZE="${BATCH_SIZE:-4096}"
UBATCH_SIZE="${UBATCH_SIZE:-2048}"
CACHE_TYPE_K="${CACHE_TYPE_K:-f16}"
CACHE_TYPE_V="${CACHE_TYPE_V:-f16}"
GPU_TYPE="${GPU_TYPE:-MI355X}"

SPEC_PERSIST="$WEIGHTS_ROOT/specialist"
SPEC_STAGE="/opt/models/specialist"
FLAG_PERSIST="$WEIGHTS_ROOT/flagship-$FLAG_QUANT"
FLAG_STAGE="/opt/models/flagship-$FLAG_QUANT"
MANIFEST_DIR="$WEIGHTS_ROOT/manifests"
LOG_FILE="/tmp/engineering.log"

mkdir -p "$MANIFEST_DIR" "$SPEC_PERSIST" "$FLAG_PERSIST" /opt/models /run
exec >> "$LOG_FILE" 2>&1

echo "boot_engineering_rocm $(date -u +%Y-%m-%dT%H:%M:%SZ) gpu=$GPU_TYPE ctx=$MAX_MODEL_LEN util=$GPU_MEM_UTIL"
vllm --version || true
rocm-smi --showproductname --showmeminfo vram || true

# Ensure curl/procps/hf_xet + cached gfx950 llama-server are ready when booting directly from base image.
if ! command -v curl >/dev/null 2>&1 || ! command -v pgrep >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y --no-install-recommends curl libcurl4 ca-certificates procps >/dev/null 2>&1 || true
fi
if ! python3 -c "import huggingface_hub, hf_xet; v = tuple(int(x) for x in huggingface_hub.__version__.split('.')[:2]); assert (1, 5) <= v < (2, 0)" >/dev/null 2>&1; then
  pip install --no-cache-dir -U "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0"
fi

LLAMA_CACHE_DIR="$WEIGHTS_ROOT/bin/llama-cpp-rocm10.2.0-gfx950"
LLAMA_CACHE_TGZ="$WEIGHTS_ROOT/bin/llama-cpp-rocm10.2.0-gfx950.tar.gz"
LLAMA_LOCAL_BIN="/opt/llama.cpp/build/bin"
ROCM_PY_LIB="$(python3 -c 'import pathlib; import _rocm_sdk_core as c; print(pathlib.Path(c.__file__).parent / "lib")' 2>/dev/null || true)"

# Restore cached llama-server tarball onto local container FS (FUSE volumes reject symlinks).
if [[ ! -x "$LLAMA_LOCAL_BIN/llama-server" ]] && [[ -s "$LLAMA_CACHE_TGZ" ]]; then
  mkdir -p "$LLAMA_LOCAL_BIN"
  tar -xzf "$LLAMA_CACHE_TGZ" -C "$LLAMA_LOCAL_BIN"
fi

# The devel wheel has no rocBLAS kernels; without this the first request aborts llama-server.
ROCBLAS_KERNELS="${ROCM_PY_LIB%/*/*}/_rocm_sdk_libraries/lib/rocblas/library"
[[ -d "$ROCBLAS_KERNELS" ]] && export ROCBLAS_TENSILE_LIBPATH="$ROCBLAS_KERNELS"

for libdir in "$LLAMA_CACHE_DIR" /opt/rocm/lib "$ROCM_PY_LIB/rocm_sysdeps/lib" "$ROCM_PY_LIB" "$LLAMA_LOCAL_BIN"; do
  if [[ -n "$libdir" && -d "$libdir" ]]; then
    export LD_LIBRARY_PATH="${libdir}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
done

if [[ -x "$LLAMA_LOCAL_BIN/llama-server" ]]; then
  export PATH="$LLAMA_LOCAL_BIN:$PATH"
  LLAMA_BIN="$LLAMA_LOCAL_BIN/llama-server"
elif [[ -x "$LLAMA_CACHE_DIR/llama-server" ]]; then
  export PATH="$LLAMA_CACHE_DIR:$PATH"
  LLAMA_BIN="$LLAMA_CACHE_DIR/llama-server"
elif command -v llama-server >/dev/null 2>&1; then
  LLAMA_BIN="$(command -v llama-server)"
else
  echo "building llama-server for gfx950 and caching archive to $LLAMA_CACHE_TGZ"
  apt-get update -qq && apt-get install -y --no-install-recommends git cmake build-essential libcurl4-openssl-dev ca-certificates
  rm -rf /src/llama.cpp
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git /src/llama.cpp
  EXTRA_FLAGS=""
  if [[ -d /opt/rocm/include/rocwmma ]] || python3 -c "import pathlib, _rocm_sdk_devel as d; assert (pathlib.Path(d.__file__).parent / 'include/rocwmma').is_dir()" >/dev/null 2>&1; then
    EXTRA_FLAGS="-DGGML_HIP_ROCWMMA_FATTN=ON"
  fi
  HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S /src/llama.cpp -B /src/llama.cpp/build \
    -DGGML_HIP=ON -DGPU_TARGETS=gfx950 ${EXTRA_FLAGS} -DCMAKE_BUILD_TYPE=Release
  cmake --build /src/llama.cpp/build --config Release --target llama-server -j 16
  mkdir -p "$LLAMA_LOCAL_BIN" "$WEIGHTS_ROOT/bin"
  cp -a /src/llama.cpp/build/bin/. "$LLAMA_LOCAL_BIN/"
  tar -czf "${LLAMA_CACHE_TGZ}.tmp" -C "$LLAMA_LOCAL_BIN" . && mv "${LLAMA_CACHE_TGZ}.tmp" "$LLAMA_CACHE_TGZ"
  export PATH="$LLAMA_LOCAL_BIN:$PATH"
  export LD_LIBRARY_PATH="$LLAMA_LOCAL_BIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  LLAMA_BIN="$LLAMA_LOCAL_BIN/llama-server"
fi
"$LLAMA_BIN" --version || true

export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

python3 - <<PY
import json, pathlib, shutil
from concurrent.futures import ThreadPoolExecutor
from huggingface_hub import model_info, snapshot_download

token_path = pathlib.Path("/run/hf.token")
token = token_path.read_text().strip() if token_path.is_file() else ""
manifest_dir = pathlib.Path("$MANIFEST_DIR")

# One S3 read stream is about 100 MB/s, so copy files side by side and keep files a previous boot already finished.
def stage_copy(persist: pathlib.Path, stage: pathlib.Path, names) -> None:
    def one(name: str) -> None:
        src, dst = persist / name, stage / name
        if dst.is_file() and dst.stat().st_size == src.stat().st_size:
            return
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(one, names))

def ensure_safetensors_model(repo: str, persist: pathlib.Path, stage: pathlib.Path) -> None:
    ready = persist / "ready.json"
    ok = False
    if ready.is_file():
        try:
            meta = json.loads(ready.read_text(encoding="utf-8"))
            files = meta.get("files") or {}
            ok = meta.get("repo") == repo and bool(files) and all((persist / k).is_file() and (persist / k).stat().st_size == v for k, v in files.items())
        except Exception:
            ok = False
    if ok:
        print(f"staging specialist from {persist} -> {stage}", flush=True)
        stage_copy(persist, stage, files)
        return
    if not (stage / "ready.json").is_file():
        print(f"downloading {repo} -> {stage}", flush=True)
        stage.mkdir(parents=True, exist_ok=True)
        snapshot_download(repo, local_dir=str(stage), token=token or None)
        files = {p.relative_to(stage).as_posix(): p.stat().st_size for p in stage.rglob("*") if p.is_file() and ".cache" not in p.parts and p.name != "ready.json"}
        (stage / "ready.json").write_text(json.dumps({"repo": repo, "files": files}) + "\n", encoding="utf-8")
    try:
        (persist / "ready.json").unlink(missing_ok=True)
        persisted = {}
        for item in sorted(p for p in stage.iterdir() if p.is_file() and p.name not in (".cache", "ready.json")):
            dst = persist / item.name
            if not dst.is_file() or dst.stat().st_size != item.stat().st_size:
                shutil.copyfile(item, dst)
            if dst.stat().st_size != item.stat().st_size:
                raise RuntimeError(f"size mismatch persisting {item.name}")
            persisted[item.name] = item.stat().st_size
        (persist / "ready.json").write_text(json.dumps({"repo": repo, "files": persisted}) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"specialist_persist_warn={exc}", flush=True)

def ensure_gguf_model(repo: str, quant: str, persist: pathlib.Path, stage: pathlib.Path) -> None:
    ready = persist / "ready.json"
    ok = False
    if ready.is_file():
        try:
            meta = json.loads(ready.read_text(encoding="utf-8"))
            files = meta.get("files") or {}
            ok = meta.get("repo") == repo and meta.get("quant") == quant and bool(files) and all((persist / k).is_file() and (persist / k).stat().st_size == v for k, v in files.items())
        except Exception:
            ok = False
    if ok:
        print(f"staging flagship from {persist} -> {stage}", flush=True)
        # Only the plain shards are served.
        stage_copy(persist, stage, [n for n in files if "-MTP-" not in n and "mmproj" not in n])
        return
    if not (stage / "ready.json").is_file():
        print(f"downloading {repo} ({quant}) -> {stage}", flush=True)
        stage.mkdir(parents=True, exist_ok=True)
        snapshot_download(repo, local_dir=str(stage), allow_patterns=[f"*{quant}*.gguf", f"*{quant.lower()}*.gguf", "*mmproj*.gguf"], token=token or None)
        files = {p.relative_to(stage).as_posix(): p.stat().st_size for p in sorted(stage.rglob("*.gguf"))}
        (stage / "ready.json").write_text(json.dumps({"repo": repo, "quant": quant, "files": files}) + "\n", encoding="utf-8")
    try:
        (persist / "ready.json").unlink(missing_ok=True)
        persisted = {}
        for item in sorted(stage.rglob("*.gguf")):
            rel = item.relative_to(stage)
            dst = persist / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.is_file() or dst.stat().st_size != item.stat().st_size:
                shutil.copyfile(item, dst)
            if dst.stat().st_size != item.stat().st_size:
                raise RuntimeError(f"size mismatch persisting {rel}")
            persisted[rel.as_posix()] = item.stat().st_size
        (persist / "ready.json").write_text(json.dumps({"repo": repo, "quant": quant, "files": persisted}) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"flagship_persist_warn={exc}", flush=True)

ensure_safetensors_model("$SPEC_REPO", pathlib.Path("$SPEC_PERSIST"), pathlib.Path("$SPEC_STAGE"))
ensure_gguf_model("$FLAG_REPO", "$FLAG_QUANT", pathlib.Path("$FLAG_PERSIST"), pathlib.Path("$FLAG_STAGE"))

lines = ["backend=engineering-rocm-gfx950"]
for label, repo in [("spec", "$SPEC_REPO"), ("flag", "$FLAG_REPO")]:
    try:
        lines.append(f"{label}_rev={model_info(repo, token=token or None).sha}")
    except Exception as exc:
        lines.append(f"{label}_rev_err={type(exc).__name__}")
manifest_dir.joinpath("engineering-runtime.txt").write_text("\n".join(lines) + "\n")
PY

KEY="$(cat /run/llm.key)"
export VLLM_API_KEY="$KEY"
export LLAMA_API_KEY="$KEY"
export VLLM_ROCM_USE_AITER="${VLLM_ROCM_USE_AITER:-1}"
export VLLM_ROCM_USE_AITER_MOE="${VLLM_ROCM_USE_AITER_MOE:-1}"

# Restore precompiled vLLM cache if persisted
VLLM_VER="$(python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo unknown)"
CACHE_ARCHIVE="$WEIGHTS_ROOT/caches/vllm-${VLLM_VER}-${GPU_TYPE}.tar.gz"
if [[ -s "$CACHE_ARCHIVE" ]] && [[ ! -d /root/.cache/vllm || -z "$(ls -A /root/.cache/vllm 2>/dev/null || true)" ]]; then
  mkdir -p /root/.cache
  tar -xzf "$CACHE_ARCHIVE" -C /root/.cache && echo "restored_vllm_cache=$CACHE_ARCHIVE" || true
fi

HELP_TEXT="$(vllm serve --help=all 2>&1 || vllm serve --help 2>&1 || true)"
VLLM_ARGS=(
  "$SPEC_STAGE"
  --served-model-name "agent-specialist"
  --host 0.0.0.0
  --port "$SPEC_PORT"
  --tensor-parallel-size 1
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-model-len "$MAX_MODEL_LEN"
  --max-num-seqs "$MAX_NUM_SEQS"
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS"
  --trust-remote-code
)
grep -q -- "--enable-prefix-caching" <<<"$HELP_TEXT" && VLLM_ARGS+=(--enable-prefix-caching)
grep -q -- "--enable-chunked-prefill" <<<"$HELP_TEXT" && VLLM_ARGS+=(--enable-chunked-prefill)
grep -q -- "--reasoning-parser" <<<"$HELP_TEXT" && VLLM_ARGS+=(--reasoning-parser qwen3)
grep -q -- "--tool-call-parser" <<<"$HELP_TEXT" && VLLM_ARGS+=(--tool-call-parser qwen3_coder)
grep -q -- "--enable-auto-tool-choice" <<<"$HELP_TEXT" && VLLM_ARGS+=(--enable-auto-tool-choice)
if [[ "$MTP_TOKENS" -gt 0 ]] && grep -q -- "--speculative-config" <<<"$HELP_TEXT"; then
  VLLM_ARGS+=(--speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":$MTP_TOKENS}")
fi

echo "launching_vllm_on_port=$SPEC_PORT util=$GPU_MEM_UTIL"
vllm serve "${VLLM_ARGS[@]}" > /tmp/specialist.log 2>&1 &
VLLM_PID=$!

# Wait for vLLM to reserve its KV pool cleanly before starting llama-server so both fit stably in 288 GB.
for i in $(seq 1 180); do
  if ! kill -0 "$VLLM_PID" 2>/dev/null; then
    echo "VLLM_EXITED_EARLY"
    tail -n 50 /tmp/specialist.log || true
    exit 1
  fi
  if curl -sf -H "Authorization: Bearer $KEY" "http://127.0.0.1:${SPEC_PORT}/v1/models" >/dev/null 2>&1; then
    echo "vllm_ready after $((i*5))s"
    break
  fi
  sleep 5
done

rocm-smi --showmeminfo vram || true

FIRST_SHARD="$(find "$FLAG_STAGE" -type f -name '*.gguf' ! -name '*mmproj*' ! -name '*draft*' | sort | head -n 1)"
if [[ -z "$FIRST_SHARD" ]]; then
  echo "NO_GGUF_SHARD_FOUND in $FLAG_STAGE"
  exit 4
fi

LLAMA_ARGS=(
  --model "$FIRST_SHARD"
  --alias "agent-flagship"
  --host 0.0.0.0
  --port "$FLAG_PORT"
  --n-gpu-layers 999
  --ctx-size "$((CTX_SIZE * PARALLEL))"  # llama-server splits this between the slots
  --parallel "$PARALLEL"
  --threads "$THREADS"
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

echo "launching_llama_server_on_port=$FLAG_PORT shard=$FIRST_SHARD"
# A flagship crash restarts the flagship only; the 27B keeps serving.
( while true; do "$LLAMA_BIN" "${LLAMA_ARGS[@]}" >> /tmp/flagship.log 2>&1 || true; echo "flagship_exited, restarting"; sleep 10; done ) &
LLAMA_PID=$!

RC=0
wait "$VLLM_PID" || RC=$?
echo "vllm_exited rc=$RC"
kill "$LLAMA_PID" 2>/dev/null || true
pkill -f "[l]lama-server" 2>/dev/null || true
exit "$RC"
