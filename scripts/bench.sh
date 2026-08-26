#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
binary="$OUTPUT_DIR_ABS/bin/llama-bench"
[[ -x "$binary" ]] || die "No staged llama-bench at $binary; include it in BUILD_TARGETS and run make build"
model_path="$(MODEL="$MODEL" "$SCRIPT_DIR/model-path.sh" --model)"
threads="$(resolve_threads "$RUNTIME_THREADS")"
case "$GPU_LAYERS" in none) gpu_layers=0 ;; *) gpu_layers=$GPU_LAYERS ;; esac
args=(-m "$model_path" -t "$threads" -ngl "$gpu_layers")
if [[ -n "${RUN_ARGS:-}" ]]; then
    read -r -a extra <<<"$RUN_ARGS"
    args+=("${extra[@]}")
fi
log "Benchmarking $(basename -- "$model_path")"
exec "$binary" "${args[@]}"
