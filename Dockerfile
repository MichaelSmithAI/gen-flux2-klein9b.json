FROM runpod/worker-comfyui:5.7.1-base

ARG HF_TOKEN

USER root

ENV COMFYUI_PATH=/comfyui
ENV COMFY_AUTO_UPDATE=1
ENV COMFYUI_ARGS="--highvram"
ENV COMFYUI_CMDLINE_ARGS="--highvram"
ENV COMMANDLINE_ARGS="--highvram"

# Ensure curl exists for runtime downloads.
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Force high VRAM mode even if base start script sets low/med VRAM.
RUN if [ -f /start.sh ]; then \
      sed -i 's/--lowvram/--highvram/g; s/--medvram/--highvram/g' /start.sh; \
    fi

# Lightweight startup downloader to avoid long image builds.
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  'log() { echo "[startup] $*"; }' \
  'download_if_missing() {' \
  '  local url="$1"' \
  '  local path="$2"' \
  '  local min_bytes="$3"' \
  '  local auth_header="$4"' \
  '  if [ -f "$path" ] && [ "$(stat -c%s "$path")" -gt "$min_bytes" ]; then' \
  '    log "Found $(basename "$path")"' \
  '    return 0' \
  '  fi' \
  '  log "Downloading $(basename "$path") from $url"' \
  '  mkdir -p "$(dirname "$path")"' \
  '  local extra_headers=()' \
  '  if [ -n "$auth_header" ]; then' \
  '    extra_headers+=(-H "$auth_header")' \
  '  elif [ -n "${HF_TOKEN:-}" ] && [[ "$url" == *huggingface.co/* ]]; then' \
  '    extra_headers+=(-H "Authorization: Bearer ${HF_TOKEN}")' \
  '  fi' \
  '  extra_headers+=(-H "User-Agent: runpod-comfyui/1.0")' \
  '  local tmp_path="${path}.tmp"' \
  '  local http_code' \
  '  http_code="$(curl -sS -L --retry 3 --retry-delay 5 --retry-connrefused -w "%{http_code}" "${extra_headers[@]}" "$url" -o "$tmp_path" || true)"' \
  '  if [ "$http_code" != "200" ]; then' \
  '    rm -f "$tmp_path"' \
  '    log "Download failed ($http_code) for $(basename "$path")"' \
  '    if [ "$http_code" = "403" ]; then' \
  '      log "403 usually means missing access/terms or invalid token for the repo."' \
  '    fi' \
  '    exit 22' \
  '  fi' \
  '  mv "$tmp_path" "$path"' \
  '  test -s "$path"' \
  '  [ "$(stat -c%s "$path")" -gt "$min_bytes" ]' \
  '}' \
  '' \
  'set_manager_network_mode() {' \
  '  local mode="$1"' \
  '  local config_paths=("/comfyui/user/__manager/config.ini" "/comfyui/user/default/ComfyUI-Manager/config.ini")' \
  '  local path' \
  '  for path in "${config_paths[@]}"; do' \
  '    if [ -f "$path" ]; then' \
  '      if grep -q "^network_mode" "$path"; then' \
  '        sed -i "s/^network_mode.*/network_mode = $mode/" "$path"' \
  '      else' \
  '        printf "\nnetwork_mode = %s\n" "$mode" >> "$path"' \
  '      fi' \
  '    fi' \
  '  done' \
  '}' \
  '' \
  'HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"' \
  'VOLUME_PATH="${RUNPOD_VOLUME_PATH:-/runpod-volume}"' \
  '' \
  'if [ "${COMFY_AUTO_UPDATE:-0}" = "1" ]; then' \
  '  log "Updating ComfyUI core + frontend (COMFY_AUTO_UPDATE=1)"' \
  '  set_manager_network_mode online' \
  '  if [ -d /comfyui/.git ]; then' \
  '    if [ "$(git -C /comfyui rev-parse --abbrev-ref HEAD)" = "HEAD" ]; then' \
  '      if git -C /comfyui show-ref --verify --quiet refs/remotes/origin/master; then' \
  '        git -C /comfyui checkout -B master origin/master' \
  '      elif git -C /comfyui show-ref --verify --quiet refs/remotes/origin/main; then' \
  '        git -C /comfyui checkout -B main origin/main' \
  '      fi' \
  '    fi' \
  '    if ! git -C /comfyui pull --rebase --autostash; then' \
  '      log "ComfyUI core update failed; continuing startup."' \
  '    fi' \
  '  else' \
  '    log "ComfyUI git repo not found; skipping core update."' \
  '  fi' \
  '  if ! comfy --skip-prompt update all; then' \
  '    log "ComfyUI-Manager update failed; continuing startup."' \
  '  fi' \
  '  if ! /opt/venv/bin/python -m pip install -r /comfyui/requirements.txt; then' \
  '    log "requirements.txt update failed; continuing startup."' \
  '  fi' \
  '  set_manager_network_mode offline' \
  'fi' \
  '' \
  'MODEL_ROOT="/comfyui/models"' \
  'if [ -d "$VOLUME_PATH" ] && [ -w "$VOLUME_PATH" ]; then' \
  '  MODEL_ROOT="$VOLUME_PATH/models"' \
  '  mkdir -p "$MODEL_ROOT"' \
  '  rm -rf /comfyui/models' \
  '  ln -s "$MODEL_ROOT" /comfyui/models' \
  '  log "Using persistent volume at $MODEL_ROOT"' \
  'fi' \
  '' \
  'mkdir -p /comfyui/models/diffusion_models /comfyui/models/text_encoders /comfyui/models/vae /comfyui/models/loras' \
  '' \
  'if [ ! -L /comfyui/models/unet ] || [ "$(readlink /comfyui/models/unet)" != "/comfyui/models/diffusion_models" ]; then' \
  '  rm -rf /comfyui/models/unet' \
  '  ln -s /comfyui/models/diffusion_models /comfyui/models/unet' \
  'fi' \
  '' \
  '' \
  'download_if_missing "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" "/comfyui/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" 1000000 ""' \
  'download_if_missing "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" "/comfyui/models/vae/flux2-vae.safetensors" 1000000 ""' \
  '' \
  'LORA_URLS_DEFAULT="https://huggingface.co/stealthagentsimon14/flux2klienkino/resolve/main/NSFW-klein.safetensors"' \
  'LORA_URLS="${LORA_URLS:-$LORA_URLS_DEFAULT}"' \
  'IFS=$'"'"'\n '"'"'' \
  'for url in $LORA_URLS; do' \
  '  [ -z "$url" ] && continue' \
  '  filename="${url##*/}"' \
  '  download_if_missing "$url" "/comfyui/models/loras/$filename" 1000000 ""' \
  'done' \
  '' \
  'MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors"' \
  'MODEL_PATH="/comfyui/models/diffusion_models/flux-2-klein-9b-fp8.safetensors"' \
  'if [ -z "${HF_TOKEN:-}" ]; then' \
  '  log "HF_TOKEN is required to download the Flux 2 Klein model."' \
  '  exit 1' \
  'fi' \
  'download_if_missing "$MODEL_URL" "$MODEL_PATH" 1000000000 "Authorization: Bearer ${HF_TOKEN}"' \
  '' \
  'if [ ! -f /comfyui/models/unet/flux-2-klein-9b-fp8.safetensors ]; then' \
  '  log "Flux 2 model missing in /comfyui/models/unet."' \
  '  exit 1' \
  'fi' \
  '' \
  'export COMFYUI_ARGS="--highvram ${COMFYUI_ARGS:-}"' \
  'export COMFYUI_CMDLINE_ARGS="--highvram ${COMFYUI_CMDLINE_ARGS:-}"' \
  'export COMMANDLINE_ARGS="--highvram ${COMMANDLINE_ARGS:-}"' \
  'exec /start.sh' \
  > /start-with-models.sh && chmod +x /start-with-models.sh

WORKDIR /
COPY input-req.json /test_input.json
CMD ["/start-with-models.sh"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD bash -lc 'test -s /comfyui/models/diffusion_models/flux-2-klein-9b-fp8.safetensors && \
    [ "$(stat -c%s /comfyui/models/diffusion_models/flux-2-klein-9b-fp8.safetensors)" -gt 1000000000 ] && \
    test -s /comfyui/models/text_encoders/qwen_3_8b_fp8mixed.safetensors && \
    [ "$(stat -c%s /comfyui/models/text_encoders/qwen_3_8b_fp8mixed.safetensors)" -gt 1000000 ] && \
    test -s /comfyui/models/vae/flux2-vae.safetensors && \
    [ "$(stat -c%s /comfyui/models/vae/flux2-vae.safetensors)" -gt 1000000 ]'