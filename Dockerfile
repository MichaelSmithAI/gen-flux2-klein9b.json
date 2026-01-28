# clean base image containing only comfyui, comfy-cli and comfyui-manager
# use latest release tag from runpod-workers/worker-comfyui
FROM runpod/worker-comfyui:5.7.1-base

# install custom nodes into comfyui (first node with --mode remote to fetch updated cache)
# No registry-verified custom nodes found.
# Could not resolve unknown_registry custom node 'MarkdownNote' (no aux_id provided)
# Could not resolve unknown_registry custom node 'MarkdownNote' (no aux_id provided)

# Force update ComfyUI to the latest version to get Flux2 nodes
RUN cd /comfyui && \
    git pull origin master && \
    pip install --no-cache-dir -r requirements.txt
    
# download models into comfyui
RUN comfy model download --url https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors --relative-path models/diffusion_models --filename flux-2-klein-9b-fp8.safetensors
RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors --relative-path models/clip --filename qwen_3_8b_fp8mixed.safetensors
RUN comfy model download --url https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/vae/flux2-vae.safetensors --relative-path models/vae --filename flux2-vae.safetensors
RUN comfy model download --url https://huggingface.co/stealthagentsimon14/flux2klienkino/blob/main/NSFW-klein.safetensors --relative-path models/loras --filename NSFW-klein.safetensors

# copy all input data (like images or videos) into comfyui (uncomment and adjust if needed)
# COPY input/ /comfyui/input/
