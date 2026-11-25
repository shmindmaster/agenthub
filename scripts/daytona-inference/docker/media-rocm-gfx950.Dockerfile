FROM rocm/pytorch:rocm10.2.0_ubuntu24.04_py3.12_pytorch_release_2.15.0
ARG COMFY_TAG=v0.46.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg sox libsox-fmt-all libsndfile1 libsndfile1-dev \
    ca-certificates curl gcc g++ procps \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/gpu-gen/server /opt/gpu-gen/logs /opt/gpu-gen/out /opt/gpu-gen/comfy-out \
 && git clone --depth 1 --branch "${COMFY_TAG}" https://github.com/Comfy-Org/ComfyUI.git /opt/gpu-gen/ComfyUI \
 && git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git /opt/gpu-gen/ComfyUI/custom_nodes/ComfyUI-GGUF

# Inherit ROCm-built PyTorch/hipBLASLt/AOTriton via --system-site-packages and pin torch so pip never pulls CUDA wheels.
RUN python3 -m venv --system-site-packages /opt/gpu-gen/venv \
 && TORCH_VER="$(python3 -c 'import torch; print(torch.__version__.split("+")[0])')" \
 && printf "torch==%s\n" "$TORCH_VER" > /tmp/torch-pin.txt \
 && grep -vE '^(torch|torchvision|torchaudio)([=<>~! ]|$)' /opt/gpu-gen/ComfyUI/requirements.txt > /tmp/comfy-reqs.txt \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir -c /tmp/torch-pin.txt -r /tmp/comfy-reqs.txt \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir -c /tmp/torch-pin.txt \
      "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0" aiohttp soundfile librosa \
      "transformers>=4.50.0" accelerate peft gguf safetensors einops sentencepiece \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir --no-deps "qwen-tts==0.1.1" \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir -c /tmp/torch-pin.txt \
      "git+https://github.com/Zyphra/ZONOS3-Mini.git" || true \
 && rm -f /tmp/torch-pin.txt /tmp/comfy-reqs.txt

COPY recipes/serve-media-rocm-gfx950.sh /opt/serve-media-rocm-gfx950.sh
RUN chmod 755 /opt/serve-media-rocm-gfx950.sh
ENTRYPOINT ["sleep", "infinity"]
