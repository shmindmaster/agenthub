FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04
ARG COMFY_TAG=v0.46.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git ffmpeg sox libsox-fmt-all \
    libsndfile1 libsndfile1-dev ca-certificates curl gcc g++ procps \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/gpu-gen/server /opt/gpu-gen/logs /opt/gpu-gen/out /opt/gpu-gen/comfy-out \
 && git clone --depth 1 --branch "${COMFY_TAG}" https://github.com/Comfy-Org/ComfyUI.git /opt/gpu-gen/ComfyUI \
 && git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git /opt/gpu-gen/ComfyUI/custom_nodes/ComfyUI-GGUF \
 && python3 -m venv /opt/gpu-gen/venv \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir -r /opt/gpu-gen/ComfyUI/requirements.txt \
 && /opt/gpu-gen/venv/bin/pip install --no-cache-dir \
      "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0" aiohttp soundfile librosa \
      "transformers>=4.50.0" accelerate peft gguf safetensors einops sentencepiece "qwen-tts==0.1.1"

COPY recipes/serve-media-cuda.sh /opt/serve-media-cuda.sh
RUN chmod 755 /opt/serve-media-cuda.sh
ENTRYPOINT ["sleep", "infinity"]
