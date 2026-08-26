#!/usr/bin/env bash
set -Eeuo pipefail

# A rendered user service points at a mode-0600 shell configuration snapshot.
# Load it before lib.sh so paths and settings do not drift when .env changes.
if [[ -n "${LLAMA_SERVER_CONFIG:-}" ]]; then
    [[ -f "$LLAMA_SERVER_CONFIG" && -r "$LLAMA_SERVER_CONFIG" ]] \
        || { printf 'ERROR: unreadable LLAMA_SERVER_CONFIG: %s\n' "$LLAMA_SERVER_CONFIG" >&2; exit 1; }
    command -v stat >/dev/null 2>&1 \
        || { printf 'ERROR: stat is required to validate LLAMA_SERVER_CONFIG\n' >&2; exit 1; }
    config_owner="$(stat -c %u -- "$LLAMA_SERVER_CONFIG")"
    config_mode="$(stat -c %a -- "$LLAMA_SERVER_CONFIG")"
    [[ "$config_owner" == "$(id -u)" ]] \
        || { printf 'ERROR: LLAMA_SERVER_CONFIG must be owned by the service user\n' >&2; exit 1; }
    [[ "$config_mode" =~ ^[0-7]{3,4}$ ]] \
        || { printf 'ERROR: could not validate LLAMA_SERVER_CONFIG permissions\n' >&2; exit 1; }
    config_mode_value=$((8#$config_mode))
    (( (config_mode_value & 077) == 0 )) \
        || { printf 'ERROR: LLAMA_SERVER_CONFIG must not be readable or writable by group/others\n' >&2; exit 1; }
    # shellcheck disable=SC1090
    set -a; source "$LLAMA_SERVER_CONFIG"; set +a
    CONFIG_FROM_MAKE=1
fi
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_service_config
binary="$OUTPUT_DIR_ABS/bin/llama-server"
[[ -x "$binary" ]] || die "No staged llama-server at $binary; run make build"

if [[ -n "$SERVER_MODEL_PATH" ]]; then
    [[ -f "$SERVER_MODEL_PATH" ]] || die "SERVER_MODEL_PATH does not exist: $SERVER_MODEL_PATH"
    gguf_magic_ok "$SERVER_MODEL_PATH" || die "SERVER_MODEL_PATH is not a GGUF file: $SERVER_MODEL_PATH"
    model_path="$(realpath -e -- "$SERVER_MODEL_PATH")"
    model_dir="$(dirname -- "$model_path")"
else
    model_path="$(MODEL="$SERVER_MODEL" "$SCRIPT_DIR/model-path.sh" --model)"
    model_dir="$(MODEL="$SERVER_MODEL" "$SCRIPT_DIR/model-path.sh" --dir)"
fi

case "$SERVER_HOST" in
    127.0.0.1|localhost|::1|'[::1]') ;;
    *) [[ -n "$SERVER_API_KEY" ]] || die "Refusing a non-loopback SERVER_HOST without SERVER_API_KEY" ;;
esac

load_mode="$SERVER_LOAD_MODE"
if [[ "$SERVER_PIN_MODEL" == "1" ]]; then
    load_mode='mmap+mlock'
    current_memlock="$(ulimit -l 2>/dev/null || printf unknown)"
    [[ "$current_memlock" == unlimited ]] || warn "Model pinning needs a sufficient memlock limit; current foreground limit is '$current_memlock'"
fi
sleep_idle="$SERVER_SLEEP_IDLE_SECONDS"
[[ "$SERVER_KEEP_MODEL_LOADED" == "0" ]] || sleep_idle=-1

gpu_layers="$SERVER_GPU_LAYERS"
[[ "$gpu_layers" != none ]] || gpu_layers=0
[[ "$SERVER_FULL_GPU_OFFLOAD" == "0" ]] || gpu_layers=all

args=(
    --model "$model_path"
    --alias "$SERVER_ALIAS"
    --host "$SERVER_HOST"
    --port "$SERVER_PORT"
    --threads "$(resolve_threads "$SERVER_THREADS")"
    --threads-batch "$(resolve_threads "$SERVER_THREADS_BATCH" logical)"
    --ctx-size "$SERVER_CTX_SIZE"
    --parallel "$SERVER_PARALLEL"
    --n-gpu-layers "$gpu_layers"
    --flash-attn "$SERVER_FLASH_ATTN"
    --load-mode "$load_mode"
    --cache-type-k "$SERVER_CACHE_TYPE_K"
    --cache-type-v "$SERVER_CACHE_TYPE_V"
    --timeout "$SERVER_TIMEOUT"
    --sleep-idle-seconds "$sleep_idle"
)
[[ -z "$SERVER_DEVICE" ]] || args+=(--device "$SERVER_DEVICE")
[[ "$SERVER_CONT_BATCHING" == "1" ]] && args+=(--cont-batching) || args+=(--no-cont-batching)
[[ "$SERVER_METRICS" == "0" ]] || args+=(--metrics)
[[ "$SERVER_EMBEDDINGS" == "0" ]] || args+=(--embeddings)
[[ "$SERVER_RERANKING" == "0" ]] || args+=(--reranking)
[[ "$SERVER_JINJA" == "1" ]] && args+=(--jinja) || args+=(--no-jinja)

if [[ -s "$model_dir/mmproj.path" ]]; then
    mmproj_relative="$(head -n1 "$model_dir/mmproj.path")"
    if [[ -n "$mmproj_relative" && "$mmproj_relative" != /* && "$mmproj_relative" != *..* \
          && -f "$model_dir/$mmproj_relative" ]]; then
        args+=(--mmproj "$model_dir/$mmproj_relative")
    fi
fi
if [[ -n "$SERVER_EXTRA_ARGS" ]]; then
    read -r -a extra <<<"$SERVER_EXTRA_ARGS"
    args+=("${extra[@]}")
fi

if [[ -n "$SERVER_API_KEY" ]]; then
    export LLAMA_API_KEY="$SERVER_API_KEY"
else
    unset LLAMA_API_KEY 2>/dev/null || true
fi
log "Starting llama-server on $SERVER_HOST:$SERVER_PORT with model $(basename -- "$model_path")"
info "load-mode=$load_mode, keep-loaded=$SERVER_KEEP_MODEL_LOADED, sleep-idle=$sleep_idle, GPU layers=$gpu_layers, parallel=$SERVER_PARALLEL"
exec "$binary" "${args[@]}"
