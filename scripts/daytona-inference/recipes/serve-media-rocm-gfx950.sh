#!/bin/bash
# Serving recipe: Slot 2 Media Lab on AMD MI355X (288 GB CDNA4 gfx950).
# Every pinned file comes from /opt/gpu-gen/server/models.json (uploaded by gpu.py before this script runs), so the
# model list lives in one place. Weights land on local disk first; a copy goes to the Daytona volume in the
# background. The volume is an S3 mount: it cannot rename or rewrite a file, so nothing downloads onto it.
#
# Two virtualenvs, both on top of the image's own torch (never reinstalled):
#   $GG/venv       ComfyUI, gateway, SOV-Transcribe, LFM3-Omni, Whisper   (transformers 5.19 to 5.22)
#   $GG/venv-qwen  Qwen3-TTS: qwen-tts 0.1.1 pins transformers 4.57.3, which the others cannot use
# Knobs: MEDIA_PROFILE=all|commercial|research (what to download), COMFY_MODE (default --highvram).
set -euo pipefail

WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/media-weights}"
PORT="${PORT:-8189}"
GG="/opt/gpu-gen"
PY="$GG/venv/bin/python"
QPY="$GG/venv-qwen/bin/python"
LOG_FILE="/tmp/media.log"
COMFY_TAG="v0.46.0"

mkdir -p "$WEIGHTS_ROOT/weights" "$GG"/{weights,caches/inductor,caches/triton,hf-cache,server,logs,out,comfy-out} /run
exec >> "$LOG_FILE" 2>&1

echo "boot_media $(date -u +%Y-%m-%dT%H:%M:%SZ) port=$PORT"
rocm-smi --showproductname --showmeminfo vram || true

export GG_BACKEND="${GG_BACKEND:-rocm}"

# System packages: ffmpeg/ffprobe (mastering, media_seconds), sox (qwen-tts), libsndfile, git (ComfyUI).
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1 || ! command -v sox >/dev/null 2>&1 \
   || ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y --no-install-recommends \
    git ffmpeg sox libsox-fmt-all libsndfile1 ca-certificates curl gcc g++ procps
fi

if [[ ! -f "$GG/ComfyUI/main.py" ]]; then
  echo "bootstrapping ComfyUI $COMFY_TAG -> $GG/ComfyUI"
  rm -rf "$GG/ComfyUI"
  git clone --depth 1 --branch "$COMFY_TAG" https://github.com/Comfy-Org/ComfyUI.git "$GG/ComfyUI"
fi

# ---- Python environments --------------------------------------------------------------------------------------
SYS_PY="$(command -v python3)"
if ! "$SYS_PY" -c "import torch" >/dev/null 2>&1; then
  if [[ "$GG_BACKEND" == "cuda" ]]; then
    "$SYS_PY" -m pip install --no-cache-dir --break-system-packages torch torchvision \
      --index-url "https://download.pytorch.org/whl/${TORCH_CUDA_TAG:-cu128}"
  else
    echo "FATAL: $SYS_PY has no torch; the ROCm image must provide it" ; exit 1
  fi
fi

ensure_uv() {
  command -v uv >/dev/null 2>&1 && return 0
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1 \
    || "$SYS_PY" -m pip install --no-cache-dir --break-system-packages uv
  command -v uv >/dev/null 2>&1
}

# A venv that sees the image's torch. Ubuntu/Debian split ensurepip into python3-venv, and a venv made from inside
# another venv (rocm/pytorch keeps torch in /opt/venv) does not inherit that venv's packages, so check, then fall back.
make_venv() {
  local dir="$1"
  [[ -x "$dir/bin/python" ]] && return 0
  rm -rf "$dir"
  if "$SYS_PY" -m venv --system-site-packages "$dir" >/dev/null 2>&1 && "$dir/bin/python" -c "import torch" >/dev/null 2>&1; then
    return 0
  fi
  rm -rf "$dir"
  ensure_uv && uv venv -q --seed --system-site-packages --python "$SYS_PY" "$dir"
  if ! "$dir/bin/python" -c "import torch" >/dev/null 2>&1; then
    local sp site
    sp="$("$SYS_PY" -c 'import os, torch; print(os.path.dirname(os.path.dirname(torch.__file__)))')"
    site="$("$dir/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    echo "$sp" > "$site/zz_image_torch.pth"
  fi
  "$dir/bin/python" -c "import torch"
}

# torchvision must be the build that matches the image's torch: a PyPI wheel of another release breaks torchvision's
# C++ ops ("operator torchvision::nms does not exist") and with it transformers imports. ComfyUI's requirements
# (through spandrel) would otherwise pull that wheel. Try the PyTorch index named in the torch tag, then the one for
# its HIP version, then the CPU build (all torchvision needs here is the pure-tensor ops).
ensure_torchvision() {
  local check='import torch, torchvision; from torchvision.ops import nms; nms(torch.zeros(1, 4), torch.zeros(1), 0.5)'
  "$PY" -c "$check" >/dev/null 2>&1 && return 0
  local full tv tag hip
  full="$("$PY" -c 'import torch; print(torch.__version__)')"
  tv="$("$PY" -c 'import re, torch; m = re.match(r"(\d+)\.(\d+)\.(\d+)", torch.__version__); print(f"0.{int(m[2]) + 15}.{m[3]}")')"
  tag=""; [[ "$full" == *+* ]] && tag="${full#*+}"
  hip="$("$PY" -c 'import torch; v = getattr(torch.version, "hip", None) or ""; print("rocm" + ".".join(v.split(".")[:2]) if v else "")')"
  local idx
  for idx in "$tag" "$hip" cpu; do
    [[ -n "$idx" ]] || continue
    [[ "$idx" == rocm* || "$idx" == cu* || "$idx" == cpu ]] || continue
    echo "torchvision==$tv from download.pytorch.org/whl/$idx"
    "$PY" -m pip install --no-cache-dir --no-deps --force-reinstall --index-url "https://download.pytorch.org/whl/$idx" "torchvision==$tv" || continue
    "$PY" -c "$check" >/dev/null 2>&1 && return 0
  done
  echo "WARNING: no torchvision $tv matching torch $full imports; ComfyUI/transformers image paths may fail"
}

# pip cache: both venvs are tarred to the volume once built and restored on the next boot (venvs hold absolute
# paths, so they go back to the same $GG). The name carries a hash of the image's Python and torch, the ComfyUI tag,
# the backend and VENV_REV: bump VENV_REV whenever a pip line below changes. Plain tar, written once and sequentially
# (the S3 mount cannot rename or rewrite); a half-written file fails the import check and is rebuilt instead.
VENV_REV="2026-11-25a"
VENV_KEY="$(printf '%s|%s|%s|%s' "$VENV_REV" "$("$SYS_PY" -c 'import sys, torch; print(sys.version_info[:2], torch.__version__)')" "$COMFY_TAG" "$GG_BACKEND" | sha1sum | cut -c1-12)"
VENV_TAR="$WEIGHTS_ROOT/bin/media-venv-$VENV_KEY.tar"
VENV_BUILT=0
if [[ ! -f "$GG/venv/.deps-ok" && -f "$VENV_TAR" ]]; then
  echo "restoring venvs from $VENV_TAR"
  if tar -xf "$VENV_TAR" -C "$GG" \
     && "$PY" -c "import aiohttp, huggingface_hub, hf_xet, transformers, soundfile, librosa, torchvision, accelerate" \
     && "$QPY" -c "import transformers, onnxruntime, sox, librosa, einops" \
     && [[ -f "$GG/venv/.deps-ok" && -f "$GG/venv-qwen/.deps-ok" ]]; then
    echo "venvs restored"
  else
    echo "venv cache unusable; rebuilding with pip"
    rm -rf "$GG/venv" "$GG/venv-qwen"
  fi
fi

if [[ ! -f "$GG/venv/.deps-ok" ]]; then
  VENV_BUILT=1
  echo "bootstrapping Python venv -> $GG/venv"
  make_venv "$GG/venv"
  ensure_torchvision
  TORCH_VER="$("$PY" -c 'import torch; print(torch.__version__.split("+")[0])')"
  TV_VER="$("$PY" -c 'import torchvision; print(torchvision.__version__.split("+")[0])')"
  # Pins keep pip from touching the image's torch/torchvision and keep SOV-Transcribe's transformers range
  # (its model card: >=5.19,<5.23). huggingface_hub 1.x: the fetch script and transformers 5 both use that API.
  printf 'torch==%s\ntorchvision==%s\ntransformers>=5.19,<5.23\nhuggingface_hub>=1.31,<2.0\n' "$TORCH_VER" "$TV_VER" > /tmp/pins.txt
  grep -vE '^(torch|torchvision|torchaudio)([=<>~! ]|$)' "$GG/ComfyUI/requirements.txt" > /tmp/comfy-reqs.txt
  "$PY" -m pip install --no-cache-dir -c /tmp/pins.txt -r /tmp/comfy-reqs.txt \
    "huggingface_hub>=1.31,<2.0" "hf_xet>=1.0.0" aiohttp soundfile librosa "transformers>=5.19,<5.23" \
    accelerate safetensors einops sentencepiece
  "$PY" -c "import aiohttp, huggingface_hub, hf_xet, transformers, soundfile, librosa, torchvision, accelerate"
  touch "$GG/venv/.deps-ok"
fi

if [[ ! -f "$GG/venv-qwen/.deps-ok" ]]; then
  VENV_BUILT=1
  echo "bootstrapping Python venv -> $GG/venv-qwen (qwen-tts)"
  make_venv "$GG/venv-qwen"
  # qwen-tts 0.1.1 asks for gradio and torchaudio; neither is used here and no torchaudio wheel matches torch 2.14+
  # (audio_worker.py stubs the one import it needs). Its other imports: sox, onnxruntime, librosa, einops.
  "$QPY" -m pip install --no-cache-dir --no-deps "qwen-tts==0.1.1"
  printf 'torch==%s\n' "$("$QPY" -c 'import torch; print(torch.__version__.split("+")[0])')" > /tmp/qpins.txt
  "$QPY" -m pip install --no-cache-dir -c /tmp/qpins.txt \
    "transformers==4.57.3" "accelerate==1.12.0" "huggingface_hub<1.0" librosa soundfile sox onnxruntime einops numpy
  touch "$GG/venv-qwen/.deps-ok"
fi

if [[ "$VENV_BUILT" == 1 && ! -e "$VENV_TAR" ]]; then
  mkdir -p "$WEIGHTS_ROOT/bin"
  echo "saving venvs -> $VENV_TAR"
  tar -cf "$VENV_TAR" --exclude='__pycache__' -C "$GG" venv venv-qwen \
    && echo "venv cache saved ($(du -h "$VENV_TAR" | cut -f1))" \
    || { echo "venv cache write failed; the next boot runs pip again"; rm -f "$VENV_TAR" 2>/dev/null || true; }
fi
# MEDIA_VENV_ONLY=1: build and cache the venvs, then stop (run on a CPU box with the same image to prefill the cache).
if [[ "${MEDIA_VENV_ONLY:-0}" == 1 ]]; then
  echo "MEDIA_VENV_ONLY: done"
  exit 0
fi

"$PY" -c "import torch; print('torch:', torch.__version__, 'hip:', getattr(torch.version, 'hip', None), 'avail:', torch.cuda.is_available(), 'dev:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)" || true

export HF_HOME="$GG/hf-cache"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"
export TORCHINDUCTOR_CACHE_DIR="$GG/caches/inductor"
export TRITON_CACHE_DIR="$GG/caches/triton"
export GG="$GG"
export GG_WEIGHTS="$GG/weights"
export GG_PERSIST="$WEIGHTS_ROOT/weights"
export GG_OUT="$GG/out"
export GG_VRAM_TOTAL_GB="${GG_VRAM_TOTAL_GB:-288}"
export PORT

# Bearer token for the gateway: the worker key gpu.py provisions, else a random one. gpu.py reads it back from here.
if [[ -s /run/llm.key ]]; then
  cp /run/llm.key "$GG/token"
  chmod 600 "$GG/token"
elif [[ ! -s "$GG/token" ]]; then
  umask 077; head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$GG/token"
  chmod 600 "$GG/token"
fi

cat > "$GG/fetch_weights.py" <<'PY'
"""fetch: pull every pinned file in models.json to local disk and link it into ComfyUI.
   persist: copy what fetch produced to the volume (S3 mount: sequential writes, no rename, no rewrite)."""
import json, os, pathlib, shutil, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed

GG = pathlib.Path(os.environ["GG"])
W = pathlib.Path(os.environ["GG_WEIGHTS"])
V = pathlib.Path(os.environ["GG_PERSIST"])
COMFY = GG / "ComfyUI" / "models"
SNAPSHOT_IGNORE = ["*.bin", "*.msgpack", "*.h5", "*.ot"]


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def jobs():
    reg = json.loads((GG / "server" / "models.json").read_text(encoding="utf-8"))
    profile = os.environ.get("MEDIA_PROFILE", "all").lower()
    only = {x for x in os.environ.get("MEDIA_ONLY", "").split(",") if x}
    seen, out = set(), []
    for m in reg["installed"]:
        if profile in ("commercial", "research") and m.get("authorization_profile") != profile:
            continue
        if only and m["id"] not in only:
            continue
        for f in m.get("files") or [{"repo": m["repo"], "revision": m["revision"], "path": "", "comfy_dir": "", "comfy_name": ""}]:
            key = (f["repo"], f["revision"], f["path"], f.get("comfy_dir", ""), f.get("comfy_name", ""))
            if key not in seen:
                seen.add(key)
                out.append({"repo": key[0], "rev": key[1], "rel": key[2], "cdir": key[3], "cname": key[4],
                            "commercial": bool(m.get("commercial"))})
    out.sort(key=lambda j: not j["commercial"])  # commercial first: those are the defaults
    return out


def from_volume(repo, rev, rel):
    """Copy from the volume when it holds this revision. ready-<rev>.json is written last, so a file it lists is whole."""
    ready = V / repo / f"ready-{rev}.json"
    if not ready.is_file():
        return False
    want = json.loads(ready.read_text())
    names = [rel] if rel else list(want)
    if not names or not all(n in want and (V / repo / n).is_file() and (V / repo / n).stat().st_size == want[n] for n in names):
        return False
    for n in names:
        dst = W / repo / n
        if not (dst.is_file() and dst.stat().st_size == want[n]):
            dst.parent.mkdir(parents=True, exist_ok=True)
            tmp = dst.with_name(dst.name + ".part")
            shutil.copyfile(V / repo / n, tmp)
            tmp.replace(dst)
    return True


def download(j):
    from huggingface_hub import get_hf_file_metadata, hf_hub_download, hf_hub_url, snapshot_download
    tok = pathlib.Path("/run/hf.token").read_text().strip() if pathlib.Path("/run/hf.token").is_file() else os.environ.get("HF_TOKEN", "")
    repo, rev, rel = j["repo"], j["rev"], j["rel"]
    dest = W / repo
    dest.mkdir(parents=True, exist_ok=True)
    if rel:
        target = dest / rel
        if from_volume(repo, rev, rel):
            log("volume", repo, rel)
        else:
            size = get_hf_file_metadata(hf_hub_url(repo, rel, revision=rev), token=tok or None).size or 0
            if not (target.is_file() and target.stat().st_size == size):
                log(f"downloading {repo}/{rel} ({size / 1e9:.2f} GB)")
                hf_hub_download(repo, rel, local_dir=str(dest), revision=rev, token=tok or None)
            if size and target.stat().st_size != size:
                raise RuntimeError(f"size mismatch {repo}/{rel}: {target.stat().st_size} != {size}")
        if j["cdir"]:
            link = COMFY / j["cdir"] / j["cname"]
            link.parent.mkdir(parents=True, exist_ok=True)
            if link.is_symlink() or link.exists():
                link.unlink()
            link.symlink_to(target)
    else:
        marker = dest / f".gg-ok-{rev}"
        if marker.is_file():
            return
        if from_volume(repo, rev, ""):
            log("volume", repo)
        else:
            log("snapshot_download", repo, rev)
            ignore = list(SNAPSHOT_IGNORE)
            snapshot_download(repo, local_dir=str(dest), revision=rev, ignore_patterns=ignore, token=tok or None)
        marker.write_text(rev)  # the gateway refuses jobs for a model without it


def run(j):
    for attempt in range(3):
        try:
            return download(j)
        except Exception as e:
            log(f"attempt {attempt + 1}/3 failed for {j['repo']}/{j['rel']}: {type(e).__name__}: {str(e)[:300]}")
            if attempt == 2:
                raise
            time.sleep(10 * (attempt + 1))


def fetch():
    todo = jobs()
    failed = []
    with ThreadPoolExecutor(6) as pool:
        futs = {pool.submit(run, j): j for j in todo}
        for fut in as_completed(futs):
            try:
                fut.result()
            except Exception:
                failed.append(futs[fut])
    ok = [j for j in todo if j not in failed]
    (W / "specs.json").write_text(json.dumps([[j["repo"], j["rev"], j["rel"]] for j in ok]))
    hard = [j for j in failed if j["commercial"]]
    for j in failed:
        log("FAILED", "commercial" if j["commercial"] else "research", j["repo"], j["rel"])
    if hard:
        sys.exit(1)  # a default model is missing: stop rather than bill an unusable box
    log("ALL_MEDIA_WEIGHTS_VERIFIED" if not failed else "MEDIA_WEIGHTS_PARTIAL (research models missing; the gateway returns 503 for them)")


def persist():
    repos = {}
    for repo, rev, rel in json.loads((W / "specs.json").read_text()):
        repos.setdefault((repo, rev), []).append(rel)
    for (repo, rev), rels in repos.items():
        src = W / repo
        files = [src / r for r in rels] if all(rels) else [p for p in src.rglob("*") if p.is_file() and ".cache" not in p.parts and not p.name.startswith(".gg-ok")]
        ready = V / repo / f"ready-{rev}.json"
        want = {p.relative_to(src).as_posix(): p.stat().st_size for p in files}
        if ready.is_file() and json.loads(ready.read_text()) == want:
            continue
        for name, size in want.items():
            dst = V / repo / name
            if dst.is_file() and dst.stat().st_size == size:
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src / name, dst)
            if dst.stat().st_size != size:
                raise RuntimeError(f"size mismatch on volume {repo}/{name}")
        try:
            if ready.exists():
                ready.unlink()
        except OSError:
            log("cannot replace", ready, "(the volume forbids it); leaving the old list")
            continue
        ready.write_text(json.dumps(want))
        log("persisted", repo, rev, len(want))
    log("PERSIST_DONE")


if __name__ == "__main__":
    {"fetch": fetch, "persist": persist}[sys.argv[1]]()
PY

"$PY" "$GG/fetch_weights.py" fetch

# ComfyUI on loopback alias 127.0.0.2:8188 (the Daytona preview proxy exposes 127.0.0.1), gateway on 0.0.0.0:$PORT.
cd "$GG/ComfyUI"
COMFY_HELP="$("$PY" main.py --help 2>&1 || true)"
COMFY_ARGS=(main.py --listen 127.0.0.2 --port 8188 "${COMFY_MODE:---highvram}" --output-directory "$GG/comfy-out" --disable-auto-launch)
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
"$PY" "$GG/fetch_weights.py" persist > "$GG/logs/persist.log" 2>&1 &

cd "$GG"
"$PY" "$GG/server/gateway.py" > "$GG/logs/gateway.log" 2>&1 &
GW_PID=$!

wait -n "$COMFY_PID" "$GW_PID"
RC=$?
echo "media_child_exited rc=$RC"
kill "$COMFY_PID" "$GW_PID" 2>/dev/null || true
exit "$RC"
