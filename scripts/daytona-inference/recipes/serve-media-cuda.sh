#!/bin/bash
# Serving recipe: Slot 2 Media Lab NVIDIA B200/H200 CUDA fallback (identical pinned weights & API contract).
set -euo pipefail

export WEIGHTS_ROOT="${WEIGHTS_ROOT:-/mnt/media-weights}"
export PORT="${PORT:-8189}"
export GG="/opt/gpu-gen"
export PY="$GG/venv/bin/python"
export GG_BACKEND="cuda"
export GG_VRAM_TOTAL_GB="${GG_VRAM_TOTAL_GB:-180}"

exec bash /opt/serve-media-rocm-gfx950.sh
