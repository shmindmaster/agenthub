FROM vllm/vllm-openai:v0.24.0
RUN pip install --no-cache-dir -U "huggingface_hub>=1.5.0,<2.0" "hf_xet>=1.0.0"
COPY recipes/serve-vllm-cuda.sh /opt/serve-vllm-cuda.sh
RUN chmod 755 /opt/serve-vllm-cuda.sh
ENTRYPOINT ["/opt/serve-vllm-cuda.sh"]
