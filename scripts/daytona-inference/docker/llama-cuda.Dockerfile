FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS builder
ARG LLAMA_CPP_REF=master
ARG CUDA_ARCHITECTURES="90;100"
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential libcurl4-openssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${LLAMA_CPP_REF}" https://github.com/ggml-org/llama.cpp.git /src/llama.cpp
RUN cmake -S /src/llama.cpp -B /src/llama.cpp/build \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
      -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /src/llama.cpp/build --config Release --target llama-server -j 16

FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libcurl4 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && pip3 install --no-cache-dir --break-system-packages "huggingface_hub>=0.30.0" "hf_xet>=1.0.0"
COPY --from=builder /src/llama.cpp/build/bin/ /opt/llama.cpp/build/bin/
ENV PATH="/opt/llama.cpp/build/bin:${PATH}"
COPY recipes/serve-llama-cuda.sh /opt/serve-llama-cuda.sh
RUN chmod 755 /opt/serve-llama-cuda.sh
ENTRYPOINT ["/opt/serve-llama-cuda.sh"]
