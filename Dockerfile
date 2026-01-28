FROM runpod/worker-comfyui:5.7.1-base

# Pass at build time, e.g. --build-arg HF_TOKEN=...
ARG HF_TOKEN

USER root

# 1. Update ComfyUI (safe CLI update)
RUN comfy --skip-prompt update all

# Ensure directories exist
RUN mkdir -p /comfyui/models/diffusion_models /comfyui/models/clip /comfyui/models/vae /comfyui/models/loras

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors --relative-path models/clip --filename qwen_3_8b_fp8mixed.safetensors

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/vae/flux2-vae.safetensors --relative-path models/vae --filename flux2-vae.safetensors

RUN comfy model download --url https://huggingface.co/stealthagentsimon14/flux2klienkino/resolve/main/NSFW-klein.safetensors --relative-path models/loras --filename NSFW-klein.safetensors

RUN rm -rf /comfyui/models/unet && \
    ln -s /comfyui/models/diffusion_models /comfyui/models/unet

# Build-time validation (no GPU)
RUN comfy --version && comfy --workspace /comfyui list
RUN test -s /comfyui/models/clip/qwen_3_8b_fp8mixed.safetensors && \
    [ $(stat -c%s "/comfyui/models/clip/qwen_3_8b_fp8mixed.safetensors") -gt 1000000 ] && \
    test -s /comfyui/models/vae/flux2-vae.safetensors && \
    [ $(stat -c%s "/comfyui/models/vae/flux2-vae.safetensors") -gt 1000000 ] && \
    test -s /comfyui/models/loras/NSFW-klein.safetensors && \
    [ $(stat -c%s "/comfyui/models/loras/NSFW-klein.safetensors") -gt 1000000 ]
RUN python - <<'PY'
import sys
sys.path.append("/comfyui")
import nodes
if "Flux2Scheduler" not in nodes.NODE_CLASS_MAPPINGS:
    raise SystemExit("Flux2Scheduler node not found in registry")
PY
COPY input-req.json /tmp/input-req.json
COPY Flux2-Klein_00542_.json /tmp/Flux2-Klein_00542_.json
RUN python - <<'PY'
import json
with open("/tmp/input-req.json", "r", encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict) or "input" not in data or "workflow" not in data["input"]:
    raise SystemExit("input-req.json missing input.workflow")
with open("/tmp/Flux2-Klein_00542_.json", "r", encoding="utf-8") as f:
    wf = json.load(f)
if "nodes" not in wf or not isinstance(wf["nodes"], list):
    raise SystemExit("Flux2-Klein_00542_.json missing nodes list")
PY

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
WORKDIR /
CMD ["/start-with-models.sh"]