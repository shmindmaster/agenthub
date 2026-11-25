FROM rocm/vllm:rocm10.2.0_ubuntu24.04_py3.14-pytorch_2.14.0_vllm-0.32.0
RUN pip install --no-cache-dir -U "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0"
COPY recipes/serve-vllm-rocm-gfx950.sh /opt/serve-vllm-rocm-gfx950.sh
RUN chmod 755 /opt/serve-vllm-rocm-gfx950.sh
ENTRYPOINT ["/opt/serve-vllm-rocm-gfx950.sh"]
