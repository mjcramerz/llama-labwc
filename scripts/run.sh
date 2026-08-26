#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
binary="$OUTPUT_DIR_ABS/bin/llama-cli"
[[ -x "$binary" ]] || die "No staged llama-cli at $binary; run make build"
model_path="$(MODEL="$MODEL" "$SCRIPT_DIR/model-path.sh" --model)"
threads="$(resolve_threads "$RUNTIME_THREADS")"
threads_batch="$(resolve_threads "$RUNTIME_THREADS_BATCH" logical)"
case "$GPU_LAYERS" in none) gpu_layers=0 ;; *) gpu_layers=$GPU_LAYERS ;; esac

args=(
    --model "$model_path"
    --threads "$threads"
    --threads-batch "$threads_batch"
    --ctx-size "$CTX_SIZE"
    --n-gpu-layers "$gpu_layers"
)
[[ -z "$RUNTIME_DEVICE" ]] || args+=(--device "$RUNTIME_DEVICE")
mmproj_path="$(MODEL="$MODEL" "$SCRIPT_DIR/model-path.sh" --mmproj 2>/dev/null || true)"
[[ -z "$mmproj_path" ]] || args+=(--mmproj "$mmproj_path")
[[ -z "${PROMPT:-}" ]] || args+=(--prompt "$PROMPT")
if [[ -n "${RUN_ARGS:-}" ]]; then
    read -r -a extra <<<"$RUN_ARGS"
    args+=("${extra[@]}")
fi
log "Running llama-cli with $threads generation thread(s), $threads_batch batch thread(s), and GPU layers '$gpu_layers'"
exec "$binary" "${args[@]}"
