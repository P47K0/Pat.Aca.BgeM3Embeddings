# bge-m3 embedding server for ACA: Hugging Face Text Embeddings Inference (CPU)
# with the model baked into the image, so a cold start never downloads ~2.2 GB.

ARG TEI_VERSION=1.9.4

# --- Stage 1: fetch the model at build time and convert it to safetensors ---
# BAAI/bge-m3 only ships pytorch_model.bin (a pickle). TEI can load that, but
# safetensors is memory-mapped and noticeably faster to start, which matters
# against the Worker's 30 s cold-start budget.
FROM python:3.12-slim AS model
RUN pip install --no-cache-dir huggingface_hub safetensors numpy torch --extra-index-url https://download.pytorch.org/whl/cpu
WORKDIR /model
RUN python - <<'PY'
from huggingface_hub import snapshot_download
import torch
from safetensors.torch import save_file

path = snapshot_download(
    "BAAI/bge-m3",
    local_dir="/model",
    # colbert/sparse heads and the onnx export aren't used by TEI's /embed.
    allow_patterns=[
        "config.json", "tokenizer.json", "tokenizer_config.json",
        "special_tokens_map.json", "sentencepiece.bpe.model",
        "modules.json", "sentence_bert_config.json", "1_Pooling/config.json",
        "pytorch_model.bin",
    ],
)
state = torch.load("/model/pytorch_model.bin", map_location="cpu", weights_only=True)
save_file({k: v.contiguous() for k, v in state.items()}, "/model/model.safetensors")
PY
RUN rm -f /model/pytorch_model.bin && rm -rf /model/.cache

# --- Stage 2: the TEI server ---
FROM ghcr.io/huggingface/text-embeddings-inference:cpu-${TEI_VERSION}
COPY --from=model /model /model

# API_KEY is supplied as an ACA secret reference; TEI reads it from the env.
# The Worker sends it as `Authorization: Bearer <key>` on /embed and /health.
ENV HF_HUB_OFFLINE=1
EXPOSE 80
# --max-batch-tokens: TEI's default (16384) makes the startup warm-up and the
# attention buffers size for 8192-token inputs, which does not fit in 4 GiB next
# to the ~2.3 GB of weights. The assistants embed short questions and site-text
# chunks, so 2048 is plenty; --auto-truncate cuts anything longer.
CMD ["--model-id", "/model", "--port", "80", "--max-client-batch-size", "32", "--max-batch-tokens", "2048", "--auto-truncate"]
