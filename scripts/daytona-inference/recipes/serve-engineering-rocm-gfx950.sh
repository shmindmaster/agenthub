#!/bin/bash
# Serving recipe: Engineering slot 1 on AMD MI355X (288 GB CDNA4 gfx950).
#   Primary: Qwen3.8-27B Quark AWQ-MXFP4 (amd/Qwen3.8-27B-Quark-AWQ-MXFP4) under vLLM ROCm on
#   :8003, 262144 ctx, 64 sequences, FP8 KV cache, multimodal vision enabled (SPEC_LANGUAGE_MODEL_ONLY=0), AITER, DFlash2 parallel
#   block-diffusion speculative decoding (incoai/Qwen3.8-27B-DFlash2, num_speculative_tokens=7),
#   16-thread CPU caps, tool calling, and separated reasoning.
#   Measured on 2026-11-26 (MI355X):
#     - 267.4 tok/s mean on-box (247.9/278.9/275.3; 312.8 thinking), 198.6 tok/s mean via gateway
#     - 156.8-157.3 tok/s on-box (~126 tok/s via gateway) on FP8 + built-in MTP (SPEC_METHOD=mtp)
#     - 81.1 tok/s baseline on FP8 with AITER + 16-thread CPU cap (without speculative decoding)
#     - 42.9 tok/s on FP8 without AITER; 29.7 tok/s on GGUF Q8_0 llama.cpp
#     - OMP_NUM_THREADS=16 (with MKL_NUM_THREADS=16, TOKENIZERS_PARALLELISM=false) is required on the
#       16-CPU cgroup running on a 192-CPU host so PyTorch/OpenMP/MKL/tokenizers do not oversubscribe 192 threads.
#   Inkling is deferred per the playbook: its weights stay on the volume, and FLAGSHIP_ENABLED=0
#   (the default) launches no second server. Set FLAGSHIP_ENABLED=1 to serve the Q8_0 GGUF again.
#   SPEC_ENGINE=llama-cpp serves the older GGUF Q8_0 primary; SPEC_METHOD=mtp uses built-in MTP.
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/opencode-weights}"
SPEC_REPO="${SPEC_REPO:-DavidAU/Qwen3.8-27B-Ultimate-Heretic-Uncensored-Turbo-Brilliance-50x-AGI-NEO-GGUF}"
SPEC_FILE="${SPEC_FILE:-Qwen3.8-27B-Ultimate-Heretic-2.1ARA-Uncn-Turbo-Brilli-50x-AGI-NEO-MTP-Q8_0.gguf}"
SPEC_MMPROJ="${SPEC_MMPROJ:-mmproj-BF16.gguf}"

FLAG_REPO="${FLAG_REPO:-Abiray/Inkling-2-Mini-Uncensored-GGUF}"
FLAG_FILE="${FLAG_FILE:-Inkling-2-Mini-Uncensored-Q8_0.gguf}"
FLAG_MMPROJ="${FLAG_MMPROJ:-mmproj-Inkling-2-Mini-Uncensored-BF16.gguf}"
FLAGSHIP_ENABLED="${FLAGSHIP_ENABLED:-0}"  # playbook: Inkling is deferred; weights stay on the volume

# Primary model engine: vllm-native serves native MXFP4/FP8 safetensors with tool calling;
# llama-cpp serves the Q8_0 GGUF (older, slower path).
SPEC_ENGINE="${SPEC_ENGINE:-vllm-native}"
SPEC_HF_REPO="${SPEC_HF_REPO:-amd/Qwen3.8-27B-Quark-AWQ-MXFP4}"
SPEC_HF_DIR="${SPEC_HF_DIR:-/opt/models/qwen-mxfp4}"
SPEC_DRAFT_REPO="${SPEC_DRAFT_REPO:-incoai/Qwen3.8-27B-DFlash2}"
SPEC_DRAFT_DIR="${SPEC_DRAFT_DIR:-/opt/models/qwen-dflash2}"
SPEC_METHOD="${SPEC_METHOD:-dflash}"
SPEC_NUM_TOKENS="${SPEC_NUM_TOKENS:-7}"
SPEC_KV_CACHE_DTYPE="${SPEC_KV_CACHE_DTYPE:-fp8}"
SPEC_LANGUAGE_MODEL_ONLY="${SPEC_LANGUAGE_MODEL_ONLY:-0}"
SPEC_TOOL_PARSER="${SPEC_TOOL_PARSER:-qwen3_coder}"
SPEC_REASONING_PARSER="${SPEC_REASONING_PARSER:-qwen3}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.90}"
SPEC_MAX_NUM_SEQS="${SPEC_MAX_NUM_SEQS:-64}"
ROCM_AITER="${ROCM_AITER:-1}"
# Cap host CPU thread pools to the 16-CPU cgroup (192-CPU host) to avoid thread oversubscription.
OMP_NUM_THREADS="${OMP_NUM_THREADS:-16}"
MKL_NUM_THREADS="${MKL_NUM_THREADS:-16}"
TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"
HIP_FORCE_DEV_KERNARG="${HIP_FORCE_DEV_KERNARG:-1}"
TORCH_BLAS_PREFER_HIPBLASLT="${TORCH_BLAS_PREFER_HIPBLASLT:-1}"

SPEC_PORT="${SPEC_PORT:-8003}"
FLAG_PORT="${FLAG_PORT:-8002}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-262144}"
# 131072 matches the served alias name (-128k) and is the size that actually loads beside the
# primary model: 1048576 tried to reserve ~406 GB of KV on a 288 GB MI355X and aborted.
CTX_SIZE="${CTX_SIZE:-131072}"
PARALLEL="${PARALLEL:-1}"
FLAG_PARALLEL="${FLAG_PARALLEL:-1}"
THREADS="${THREADS:-16}"
BATCH_SIZE="${BATCH_SIZE:-4096}"
UBATCH_SIZE="${UBATCH_SIZE:-2048}"
CACHE_TYPE_K="${CACHE_TYPE_K:-f16}"
CACHE_TYPE_V="${CACHE_TYPE_V:-f16}"
FLAG_CACHE_TYPE_K="${FLAG_CACHE_TYPE_K:-q8_0}"
FLAG_CACHE_TYPE_V="${FLAG_CACHE_TYPE_V:-q8_0}"
GPU_TYPE="${GPU_TYPE:-MI355X}"

SPEC_PERSIST="$WEIGHTS_ROOT/specialist-q8"
SPEC_STAGE="/opt/models/specialist-q8"
FLAG_PERSIST="$WEIGHTS_ROOT/inkling-q8"
FLAG_STAGE="/opt/models/inkling-q8"
MANIFEST_DIR="$WEIGHTS_ROOT/manifests"
LOG_FILE="/tmp/engineering.log"

mkdir -p "$MANIFEST_DIR" "$SPEC_PERSIST" "$FLAG_PERSIST" /opt/models /run
exec >> "$LOG_FILE" 2>&1

echo "boot_engineering_dual_q8 $(date -u +%Y-%m-%dT%H:%M:%SZ) gpu=$GPU_TYPE spec_ctx=$MAX_MODEL_LEN flag_ctx=$CTX_SIZE"
rocm-smi --showproductname --showmeminfo vram || true

# Ensure curl/procps/hf_xet + cached gfx950 llama-server are ready.
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
from huggingface_hub import hf_hub_download, model_info

token_path = pathlib.Path("/run/hf.token")
token = token_path.read_text().strip() if token_path.is_file() else ""
manifest_dir = pathlib.Path("$MANIFEST_DIR")

def stage_copy(persist: pathlib.Path, stage: pathlib.Path, names) -> None:
    def one(name: str) -> None:
        src, dst = persist / name, stage / name
        if dst.is_file() and dst.stat().st_size == src.stat().st_size:
            return
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    with ThreadPoolExecutor(4) as pool:
        list(pool.map(one, names))

def ensure_exact_gguf(label: str, repo: str, filenames: list[str], persist: pathlib.Path, stage: pathlib.Path) -> None:
    filenames = [f for f in filenames if f]
    ready = persist / "ready.json"
    ok = False
    files = {}
    if ready.is_file():
        try:
            meta = json.loads(ready.read_text(encoding="utf-8"))
            files = meta.get("files") or {}
            ok = (
                meta.get("repo") == repo
                and all(f in files for f in filenames)
                and all((persist / f).is_file() and (persist / f).stat().st_size == files[f] for f in filenames)
            )
        except Exception:
            ok = False
    if ok:
        print(f"staging {label} from {persist} -> {stage}", flush=True)
        stage_copy(persist, stage, filenames)
        return

    stage.mkdir(parents=True, exist_ok=True)
    stage_ready = stage / "ready.json"
    stage_ok = False
    if stage_ready.is_file():
        try:
            smeta = json.loads(stage_ready.read_text(encoding="utf-8"))
            sfiles = smeta.get("files") or {}
            stage_ok = (
                smeta.get("repo") == repo
                and all(f in sfiles and (stage / f).is_file() and (stage / f).stat().st_size == sfiles[f] for f in filenames)
            )
        except Exception:
            stage_ok = False
    if not stage_ok:
        for fn in filenames:
            print(f"downloading {label} {repo}/{fn} -> {stage}", flush=True)
            hf_hub_download(repo, fn, local_dir=str(stage), token=token or None)
        sfiles = {fn: (stage / fn).stat().st_size for fn in filenames}
        stage_ready.write_text(json.dumps({"repo": repo, "files": sfiles}) + "\n", encoding="utf-8")

    try:
        ready.unlink(missing_ok=True)
        persisted = {}
        for fn in filenames:
            src = stage / fn
            dst = persist / fn
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.is_file() or dst.stat().st_size != src.stat().st_size:
                shutil.copyfile(src, dst)
            if dst.stat().st_size != src.stat().st_size:
                raise RuntimeError(f"size mismatch persisting {fn}")
            persisted[fn] = src.stat().st_size
        ready.write_text(json.dumps({"repo": repo, "files": persisted}) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"{label}_persist_warn={exc}", flush=True)

ensure_exact_gguf("specialist", "$SPEC_REPO", ["$SPEC_FILE", "$SPEC_MMPROJ"], pathlib.Path("$SPEC_PERSIST"), pathlib.Path("$SPEC_STAGE"))
ensure_exact_gguf("flagship", "$FLAG_REPO", ["$FLAG_FILE", "$FLAG_MMPROJ"], pathlib.Path("$FLAG_PERSIST"), pathlib.Path("$FLAG_STAGE"))

lines = ["backend=engineering-rocm-gfx950-dual-q8"]
for label, repo in [("spec", "$SPEC_REPO"), ("flag", "$FLAG_REPO")]:
    try:
        lines.append(f"{label}_rev={model_info(repo, token=token or None).sha}")
    except Exception as exc:
        lines.append(f"{label}_rev_err={type(exc).__name__}")
manifest_dir.joinpath("engineering-runtime.txt").write_text("\n".join(lines) + "\n")
PY

KEY="$(cat /run/llm.key)"
export LLAMA_API_KEY="$KEY"
LLAMA_HELP="$("$LLAMA_BIN" --help 2>&1 || true)"

SPEC_MODEL_PATH="$SPEC_STAGE/$SPEC_FILE"
SPEC_MMPROJ_PATH="$SPEC_STAGE/$SPEC_MMPROJ"
FLAG_MODEL_PATH="$FLAG_STAGE/$FLAG_FILE"
FLAG_MMPROJ_PATH="$FLAG_STAGE/$FLAG_MMPROJ"

if [[ ! -f "$FLAG_MODEL_PATH" ]]; then
  echo "MISSING_MODEL_FILE flag=$FLAG_MODEL_PATH"
  exit 4
fi
if [[ "$SPEC_ENGINE" == "llama-cpp" && ! -f "$SPEC_MODEL_PATH" ]]; then
  echo "MISSING_MODEL_FILE spec=$SPEC_MODEL_PATH (needed by SPEC_ENGINE=llama-cpp)"
  exit 4
fi

# True when a staged Hugging Face snapshot is present and every recorded file matches its size.
hf_dir_ready() {
  python3 - "$1" "$2" <<'PY'
import json, pathlib, sys
target, repo = pathlib.Path(sys.argv[1]), sys.argv[2]
marker = target / "ready.json"
if not (marker.is_file() and (target / "config.json").is_file()):
    raise SystemExit(1)
try:
    meta = json.loads(marker.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)
if meta.get("repo") != repo:
    raise SystemExit(1)
for name, size in (meta.get("files") or {}).items():
    path = target / name
    if not path.is_file() or path.stat().st_size != size:
        raise SystemExit(1)
raise SystemExit(0)
PY
}

stage_hf_snapshot() {
  local dir="$1"
  local repo="$2"
  hf_dir_ready "$dir" "$repo" && { echo "hf_snapshot_present $dir ($repo)"; return 0; }
  echo "staging_hf_snapshot $repo -> $dir"
  python3 - "$dir" "$repo" <<'PY'
import json, pathlib, sys
from huggingface_hub import snapshot_download
target, repo = pathlib.Path(sys.argv[1]), sys.argv[2]
target.mkdir(parents=True, exist_ok=True)
token_path = pathlib.Path("/run/hf.token")
token = token_path.read_text().strip() if token_path.is_file() else None
snapshot_download(repo, local_dir=str(target), token=token or None)
files = {
    str(p.relative_to(target)): p.stat().st_size
    for p in target.rglob("*")
    if p.is_file() and p.name != "ready.json"
}
(target / "ready.json").write_text(
    json.dumps({"repo": repo, "files": files}) + "\n", encoding="utf-8"
)
PY
}

stage_native() {
  stage_hf_snapshot "$SPEC_HF_DIR" "$SPEC_HF_REPO"
  if [[ "$SPEC_METHOD" == "dflash" ]]; then
    stage_hf_snapshot "$SPEC_DRAFT_DIR" "$SPEC_DRAFT_REPO"
  fi
}

launch_spec() {
  if [[ "$SPEC_ENGINE" == "llama-cpp" ]]; then
    local args=(
      --model "$SPEC_MODEL_PATH"
      --alias "qwen3.8-27b-unc-q8"
      --host 0.0.0.0
      --port "$SPEC_PORT"
      --n-gpu-layers 999
      --ctx-size "$((MAX_MODEL_LEN * PARALLEL))"
      --parallel "$PARALLEL"
      --threads "$THREADS"
      --flash-attn on
      --batch-size "$BATCH_SIZE"
      --ubatch-size "$UBATCH_SIZE"
      --cache-prompt
      --cache-type-k "$CACHE_TYPE_K"
      --cache-type-v "$CACHE_TYPE_V"
      --jinja
      --metrics
    )
    [[ -f "$SPEC_MMPROJ_PATH" ]] && args+=(--mmproj "$SPEC_MMPROJ_PATH")
    grep -q -- "--reasoning" <<<"$LLAMA_HELP" && args+=(--reasoning on --reasoning-effort medium)
    echo "launching_specialist_q8_on_port=$SPEC_PORT model=$SPEC_MODEL_PATH ctx=$((MAX_MODEL_LEN * PARALLEL)) parallel=$PARALLEL"
    setsid "$LLAMA_BIN" "${args[@]}" > /tmp/specialist.log 2>&1 &
  else
    echo "launching_native_qwen_vllm port=$SPEC_PORT model=$SPEC_HF_DIR ctx=$MAX_MODEL_LEN kv=$SPEC_KV_CACHE_DTYPE seqs=$SPEC_MAX_NUM_SEQS tool_parser=$SPEC_TOOL_PARSER reasoning_parser=$SPEC_REASONING_PARSER aiter=$ROCM_AITER spec_method=$SPEC_METHOD spec_tokens=$SPEC_NUM_TOKENS omp_threads=$OMP_NUM_THREADS"
    local vllm_args=(
      --model "$SPEC_HF_DIR"
      --served-model-name qwen3.8-27b-unc-q8
      --host 0.0.0.0 --port "$SPEC_PORT"
      --max-model-len "$MAX_MODEL_LEN"
      --gpu-memory-utilization "$GPU_MEM_UTIL"
      --max-num-seqs "$SPEC_MAX_NUM_SEQS"
      --max-num-batched-tokens 16384
      --tensor-parallel-size 1
      --kv-cache-dtype "$SPEC_KV_CACHE_DTYPE"
      --enable-prefix-caching
      --enable-chunked-prefill
      --enable-auto-tool-choice
      --tool-call-parser "$SPEC_TOOL_PARSER"
      --reasoning-parser "$SPEC_REASONING_PARSER"
    )
    [[ "${SPEC_LANGUAGE_MODEL_ONLY:-0}" == "1" ]] && vllm_args+=(--language-model-only)
    if [[ "${SPEC_NUM_TOKENS:-0}" -gt 0 ]]; then
      if [[ "$SPEC_METHOD" == "dflash" ]]; then
        vllm_args+=(--speculative-config "{\"method\":\"dflash\",\"model\":\"${SPEC_DRAFT_DIR}\",\"num_speculative_tokens\":${SPEC_NUM_TOKENS}}")
      elif [[ "$SPEC_METHOD" != "none" ]]; then
        vllm_args+=(--speculative-config "{\"method\":\"${SPEC_METHOD}\",\"num_speculative_tokens\":${SPEC_NUM_TOKENS}}")
      fi
    fi
    # VLLM_API_KEY keeps the worker key out of the process command line.
    VLLM_API_KEY="$KEY" VLLM_ROCM_USE_AITER="$ROCM_AITER" VLLM_ROCM_USE_AITER_MHA="$ROCM_AITER" VLLM_ROCM_USE_AITER_RMSNORM="$ROCM_AITER" \
      AITER_ROCM_ARCH="gfx942;gfx950" \
      OMP_NUM_THREADS="$OMP_NUM_THREADS" MKL_NUM_THREADS="$MKL_NUM_THREADS" TOKENIZERS_PARALLELISM="$TOKENIZERS_PARALLELISM" \
      HIP_FORCE_DEV_KERNARG="$HIP_FORCE_DEV_KERNARG" TORCH_BLAS_PREFER_HIPBLASLT="$TORCH_BLAS_PREFER_HIPBLASLT" \
      setsid python3 -m vllm.entrypoints.openai.api_server "${vllm_args[@]}" \
      >> /tmp/specialist.log 2>&1 &
  fi
  SPEC_PID=$!
}

[[ "$SPEC_ENGINE" != "llama-cpp" ]] && stage_native
launch_spec

for i in $(seq 1 240); do
  if ! kill -0 "$SPEC_PID" 2>/dev/null; then
    echo "SPECIALIST_EXITED_EARLY"
    tail -n 80 /tmp/specialist.log || true
    exit 1
  fi
  if curl -sf -H "Authorization: Bearer $KEY" "http://127.0.0.1:${SPEC_PORT}/v1/models" >/dev/null 2>&1; then
    echo "specialist_ready after $((i*3))s engine=$SPEC_ENGINE"
    break
  fi
  sleep 3
done

rocm-smi --showmeminfo vram || true

launch_flagship() {
  local par="$1"
  local args=(
    --model "$FLAG_MODEL_PATH"
    --alias "inkling2-min-26b-unc-q8-128k"
    --host 0.0.0.0
    --port "$FLAG_PORT"
    --n-gpu-layers 999
    --ctx-size "$((CTX_SIZE * par))"
    --parallel "$par"
    --threads "$THREADS"
    --flash-attn on
    --batch-size "$BATCH_SIZE"
    --ubatch-size "$UBATCH_SIZE"
    --cache-prompt
    --cache-type-k "$FLAG_CACHE_TYPE_K"
    --cache-type-v "$FLAG_CACHE_TYPE_V"
    --jinja
    --temp 1.0
    --top-p 0.95
    --metrics
  )
  [[ -f "$FLAG_MMPROJ_PATH" ]] && args+=(--mmproj "$FLAG_MMPROJ_PATH")
  grep -q -- "--reasoning" <<<"$LLAMA_HELP" && args+=(--reasoning on --reasoning-effort medium)
  echo "launching_flagship_q8_on_port=$FLAG_PORT model=$FLAG_MODEL_PATH ctx=$((CTX_SIZE * par)) parallel=$par"
  "$LLAMA_BIN" "${args[@]}" >> /tmp/flagship.log 2>&1
}

ACTIVE_FLAG_PAR="$FLAG_PARALLEL"
if [[ "$FLAGSHIP_ENABLED" == "1" ]]; then
  (
    while true; do
      if ! launch_flagship "$ACTIVE_FLAG_PAR"; then
        echo "flagship_exited parallel=$ACTIVE_FLAG_PAR"
        if [[ "$ACTIVE_FLAG_PAR" -gt 1 ]]; then
          echo "falling back to flagship parallel=1"
          ACTIVE_FLAG_PAR=1
        fi
      fi
      sleep 5
    done
  ) &
  FLAG_SUP_PID=$!
else
  # Playbook: Inkling is deferred, so the whole engineering GPU belongs to the FP8 primary.
  echo "flagship_disabled FLAGSHIP_ENABLED=0 (Inkling deferred; weights retained on the volume)"
  FLAG_SUP_PID=""
fi

RC=0
wait "$SPEC_PID" || RC=$?
echo "specialist_exited rc=$RC"
# Kill only this slot's own servers, matched by their port. A blanket `pkill -f llama-server`
# also killed the sibling Inkling server on 2026-11-26, leaving both gateway aliases without a
# backend while the box still looked healthy.
kill "$FLAG_SUP_PID" 2>/dev/null || true
pkill -f "llama-server.*--port ${FLAG_PORT} " 2>/dev/null || true
pkill -f "vllm.entrypoints.openai.api_server.*--port ${SPEC_PORT} " 2>/dev/null || true
exit "$RC"
