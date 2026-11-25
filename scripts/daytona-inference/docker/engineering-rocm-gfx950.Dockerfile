FROM rocm/dev-ubuntu-24.04:10.2.0-full AS llama-builder
ARG LLAMA_CPP_REF=master
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential libcurl4-openssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${LLAMA_CPP_REF}" https://github.com/ggml-org/llama.cpp.git /src/llama.cpp
RUN EXTRA_FLAGS="" \
 && if [ -d /opt/rocm/include/rocwmma ]; then EXTRA_FLAGS="-DGGML_HIP_ROCWMMA_FATTN=ON"; fi \
 && HIPCXX="$(hipconfig -l)/clang" \
    HIP_PATH="$(hipconfig -R)" \
    cmake -S /src/llama.cpp -B /src/llama.cpp/build \
      -DGGML_HIP=ON \
      -DGPU_TARGETS=gfx950 \
      ${EXTRA_FLAGS} \
      -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /src/llama.cpp/build --config Release --target llama-server -j 16

FROM rocm/vllm:rocm10.2.0_ubuntu24.04_py3.14-pytorch_2.14.0_vllm-0.32.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 ca-certificates procps \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir -U "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0"
COPY --from=llama-builder /src/llama.cpp/build/bin/ /opt/llama.cpp/build/bin/
ENV PATH="/opt/llama.cpp/build/bin:${PATH}"
COPY recipes/serve-engineering-rocm-gfx950.sh /opt/serve-engineering-rocm-gfx950.sh
RUN chmod 755 /opt/serve-engineering-rocm-gfx950.sh
ENTRYPOINT ["sleep", "infinity"]
