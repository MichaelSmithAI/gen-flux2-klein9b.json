FROM runpod/worker-comfyui:5.7.1-base

# Pass at build time, e.g. --build-arg HF_TOKEN=...
ARG HF_TOKEN

USER root

# 1. Update ComfyUI
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN cd /comfyui && \
    git pull origin master && \
    pip install --no-cache-dir -r requirements.txt

# Ensure directories exist
RUN mkdir -p /comfyui/models/diffusion_models /comfyui/models/clip /comfyui/models/vae /comfyui/models/loras

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors --relative-path models/clip --filename qwen_3_8b_fp8mixed.safetensors

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/vae/flux2-vae.safetensors --relative-path models/vae --filename flux2-vae.safetensors

RUN comfy model download --url https://huggingface.co/stealthagentsimon14/flux2klienkino/resolve/main/NSFW-klein.safetensors --relative-path models/loras --filename NSFW-klein.safetensors

RUN rm -rf /comfyui/models/unet && \
    ln -s /comfyui/models/diffusion_models /comfyui/models/unet

# Download gated model at runtime using HF_TOKEN and verify symlink
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  'MODEL_PATH="/comfyui/models/diffusion_models/flux-2-klein-9b-fp8.safetensors"' \
  'MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors"' \
  '' \
  'if [ ! -f "${MODEL_PATH}" ] || [ "$(stat -c%s "${MODEL_PATH}")" -le 1000000000 ]; then' \
  '  if [ -z "${HF_TOKEN:-}" ]; then' \
  '    echo "HF_TOKEN is required to download the Flux 2 Klein model." >&2' \
  '    exit 1' \
  '  fi' \
  '  echo "Downloading Flux 2 Klein model..."' \
  '  curl -fL -H "Authorization: Bearer ${HF_TOKEN}" "${MODEL_URL}" -o "${MODEL_PATH}"' \
  '  test -s "${MODEL_PATH}"' \
  '  [ "$(stat -c%s "${MODEL_PATH}")" -gt 1000000000 ]' \
  'fi' \
  '' \
  'if [ ! -L /comfyui/models/unet ] || [ "$(readlink /comfyui/models/unet)" != "/comfyui/models/diffusion_models" ]; then' \
  '  rm -rf /comfyui/models/unet' \
  '  ln -s /comfyui/models/diffusion_models /comfyui/models/unet' \
  'fi' \
  '' \
  'if [ ! -f /comfyui/models/unet/flux-2-klein-9b-fp8.safetensors ]; then' \
  '  echo "Flux 2 model missing in /comfyui/models/unet." >&2' \
  '  exit 1' \
  'fi' \
  '' \
  'exec /start.sh' \
  > /start-with-models.sh && chmod +x /start-with-models.sh

ENV COMFYUI_PATH=/comfyui
CMD ["/start-with-models.sh"]