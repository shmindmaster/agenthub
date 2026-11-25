FROM rocm/dev-ubuntu-24.04:7.0 AS builder
ARG LLAMA_CPP_REF=master
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential libcurl4-openssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${LLAMA_CPP_REF}" https://github.com/ggml-org/llama.cpp.git /src/llama.cpp
RUN HIPCXX="$(hipconfig -l)/clang" \
    HIP_PATH="$(hipconfig -R)" \
    cmake -S /src/llama.cpp -B /src/llama.cpp/build \
      -DGGML_HIP=ON \
      -DGPU_TARGETS=gfx950 \
      -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /src/llama.cpp/build --config Release --target llama-server -j 16

FROM rocm/dev-ubuntu-24.04:7.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libcurl4 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && pip3 install --no-cache-dir --break-system-packages "huggingface_hub>=0.30.0" "hf_xet>=1.0.0"
COPY --from=builder /src/llama.cpp/build/bin/ /opt/llama.cpp/build/bin/
ENV PATH="/opt/llama.cpp/build/bin:${PATH}"
COPY recipes/serve-llama-hip-gfx950.sh /opt/serve-llama-hip-gfx950.sh
RUN chmod 755 /opt/serve-llama-hip-gfx950.sh
ENTRYPOINT ["/opt/serve-llama-hip-gfx950.sh"]
