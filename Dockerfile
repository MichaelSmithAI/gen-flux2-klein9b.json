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

# 3. Download Model with Token (Gated)
RUN test -n "${HF_TOKEN}"
RUN curl -H "Authorization: Bearer ${HF_TOKEN}" -L https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors -o /comfyui/models/diffusion_models/flux-2-klein-9b-fp8.safetensors

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors --relative-path models/clip --filename qwen_3_8b_fp8mixed.safetensors

RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/vae/flux2-vae.safetensors --relative-path models/vae --filename flux2-vae.safetensors

RUN comfy model download --url https://huggingface.co/stealthagentsimon14/flux2klienkino/resolve/main/NSFW-klein.safetensors --relative-path models/loras --filename NSFW-klein.safetensors

# CRITICAL: Create symlink so UNETLoader can find the model
# Remove the empty unet folder first if it exists, then create symlink
RUN rm -rf /comfyui/models/unet && \
    ln -s /comfyui/models/diffusion_models /comfyui/models/unet

ENV COMFYUI_PATH=/comfyui