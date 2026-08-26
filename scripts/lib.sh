#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ROOT_DIR="${ROOT_DIR:-$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)}"
ROOT_DIR="$(cd -- "$ROOT_DIR" >/dev/null 2>&1 && pwd -P)"

# Direct script invocation reads .env. Make exports its resolved values and sets
# CONFIG_FROM_MAKE=1, preserving command-line overrides such as ENABLE_CUDA=1.
if [[ "${CONFIG_FROM_MAKE:-0}" != "1" && -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

: "${LLAMA_CPP_REPO:=https://github.com/ggml-org/llama.cpp.git}"
: "${LLAMA_CPP_REF:=b10270}"
: "${SOURCE_DIR:=.cache/llama.cpp}"
: "${BUILD_DIR:=.build/native}"
: "${OUTPUT_DIR:=output}"
: "${MODEL_DIR:=output/models}"
: "${CMAKE_GENERATOR:=auto}"
BUILDER_CMAKE_GENERATOR="$CMAKE_GENERATOR"
unset CMAKE_GENERATOR
: "${BUILD_JOBS:=auto}"
: "${CMAKE_C_COMPILER:=}"
: "${CMAKE_CXX_COMPILER:=}"
: "${BUILD_TARGETS:=llama-cli llama-server llama-bench llama-quantize llama-gguf-split}"
: "${GGML_NATIVE:=1}"
: "${ENABLE_LTO:=1}"
: "${ENABLE_CCACHE:=1}"
: "${ENABLE_OPENMP:=1}"
: "${ENABLE_CPU_REPACK:=1}"
: "${ENABLE_LLAMAFILE:=1}"
: "${ENABLE_FAST_MATH:=0}"
: "${ENABLE_BLAS:=0}"
: "${BLAS_VENDOR:=OpenBLAS}"
: "${ENABLE_CUDA:=0}"
: "${CUDA_ARCHS:=auto}"
: "${ENABLE_CUDA_FA:=1}"
: "${ENABLE_CUDA_FA_ALL_QUANTS:=0}"
: "${ENABLE_CUDA_GRAPHS:=1}"
: "${ENABLE_CUDA_NCCL:=0}"
: "${CUDA_FORCE_MMQ:=0}"
: "${CUDA_FORCE_CUBLAS:=0}"
: "${ENABLE_HIP:=0}"
: "${AMDGPU_TARGETS:=auto}"
: "${ENABLE_HIP_GRAPHS:=1}"
: "${ENABLE_HIP_RCCL:=0}"
: "${ENABLE_VULKAN:=0}"
: "${ENABLE_SYCL:=0}"
: "${ENABLE_SYCL_F16:=0}"
: "${SYCL_TARGET:=INTEL}"
: "${SYCL_DEVICE_ARCH:=}"
: "${ENABLE_OPENCL:=0}"
: "${ENABLE_OPENVINO:=0}"
: "${ENABLE_RPC:=0}"
: "${ENABLE_SERVER_UI:=0}"
: "${USE_PREBUILT_UI:=0}"
: "${ENABLE_OPENSSL:=0}"
: "${ENABLE_LLGUIDANCE:=0}"
: "${STRIP_BINARIES:=1}"
: "${OFFLINE:=0}"
: "${SOURCE_UPDATE:=0}"
: "${FORCE_SOURCE_RESET:=0}"
: "${ALLOW_EXTERNAL_DIRS:=0}"
: "${EXTRA_CMAKE_ARGS:=}"
: "${EXTRA_C_FLAGS:=}"
: "${EXTRA_CXX_FLAGS:=}"

: "${MODEL:=}"
: "${HF_REPO:=}"
: "${HF_FILE:=}"
: "${HF_QUANT:=Q4_K_M}"
: "${HF_REVISION:=main}"
: "${HF_TOKEN:=}"
: "${HF_API_BASE:=https://huggingface.co/api/models}"
: "${HF_DOWNLOAD_BASE:=https://huggingface.co}"
: "${DOWNLOAD_MMPROJ:=0}"
: "${VERIFY_REMOTE_SHA256:=1}"
: "${STRICT_CHECKSUM:=0}"
: "${STRICT_RESOURCES:=0}"
: "${FORCE_DOWNLOAD:=0}"
: "${DOWNLOAD_RETRIES:=4}"
: "${DOWNLOAD_CONNECT_TIMEOUT:=20}"

: "${PROMPT:=Write a concise explanation of why native CPU compilation can improve inference speed.}"
: "${RUN_ARGS:=}"
: "${RUNTIME_THREADS:=auto}"
: "${RUNTIME_THREADS_BATCH:=auto}"
: "${GPU_LAYERS:=auto}"
: "${RUNTIME_DEVICE:=}"
: "${CTX_SIZE:=8192}"

: "${ENABLE_USER_SERVICE:=0}"
: "${SERVICE_NAME:=llama-server-native}"
: "${SERVICE_AUTOSTART:=1}"
: "${SERVICE_START_NOW:=1}"
: "${SERVICE_RESTART:=on-failure}"
: "${SERVICE_RESTART_SEC:=3}"
: "${SERVICE_TIMEOUT_STOP_SEC:=90}"
: "${SERVER_MODEL:=qwen3.5-0.8b-q4_k_m}"
: "${SERVER_MODEL_PATH:=}"
: "${SERVER_ALIAS:=local-model}"
: "${SERVER_HOST:=127.0.0.1}"
: "${SERVER_PORT:=8080}"
: "${SERVER_THREADS:=auto}"
: "${SERVER_THREADS_BATCH:=auto}"
: "${SERVER_CTX_SIZE:=8192}"
: "${SERVER_PARALLEL:=1}"
: "${SERVER_GPU_LAYERS:=auto}"
: "${SERVER_DEVICE:=}"
: "${SERVER_FLASH_ATTN:=auto}"
: "${SERVER_LOAD_MODE:=mmap}"
: "${SERVER_KEEP_MODEL_LOADED:=1}"
: "${SERVER_SLEEP_IDLE_SECONDS:=300}"
: "${SERVER_PIN_MODEL:=0}"
: "${SERVER_FULL_GPU_OFFLOAD:=0}"
: "${SERVER_CACHE_TYPE_K:=f16}"
: "${SERVER_CACHE_TYPE_V:=f16}"
: "${SERVER_CONT_BATCHING:=1}"
: "${SERVER_METRICS:=0}"
: "${SERVER_EMBEDDINGS:=0}"
: "${SERVER_RERANKING:=0}"
: "${SERVER_JINJA:=1}"
: "${SERVER_API_KEY:=}"
: "${SERVER_TIMEOUT:=3600}"
: "${SERVER_EXTRA_ARGS:=}"

resolve_path() {
    local path=$1 joined
    if [[ "$path" = /* ]]; then joined="$path"; else joined="$ROOT_DIR/$path"; fi
    if command -v realpath >/dev/null 2>&1; then realpath -m -- "$joined"; else printf '%s\n' "$joined"; fi
}

SOURCE_DIR_ABS="$(resolve_path "$SOURCE_DIR")"
BUILD_DIR_ABS="$(resolve_path "$BUILD_DIR")"
OUTPUT_DIR_ABS="$(resolve_path "$OUTPUT_DIR")"
MODEL_DIR_ABS="$(resolve_path "$MODEL_DIR")"
MANIFEST_PATH="$ROOT_DIR/models/models.tsv"

if [[ -t 2 && "${NO_COLOR:-0}" != "1" ]]; then
    _BLUE='\033[1;34m'; _CYAN='\033[1;36m'; _YELLOW='\033[1;33m'; _RED='\033[1;31m'; _RESET='\033[0m'
else
    _BLUE=''; _CYAN=''; _YELLOW=''; _RED=''; _RESET=''
fi
log()  { printf '%b==>%b %s\n' "$_BLUE" "$_RESET" "$*" >&2; }
info() { printf '%b  ->%b %s\n' "$_CYAN" "$_RESET" "$*" >&2; }
warn() { printf '%bWARN:%b %s\n' "$_YELLOW" "$_RESET" "$*" >&2; }
die()  { printf '%bERROR:%b %s\n' "$_RED" "$_RESET" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
validate_bool() {
    local name=$1 value=${!1:-}
    case "$value" in 0|1) ;; *) die "$name must be 0 or 1, got: '$value'" ;; esac
}
validate_uint() {
    local name=$1 value=${!1:-} allow_zero=${2:-1}
    [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be an unsigned integer, got: '$value'"
    [[ "$allow_zero" != "0" || "$value" != "0" ]] || die "$name must be greater than zero"
}
cmake_bool() { [[ "$1" == "1" ]] && printf 'ON\n' || printf 'OFF\n'; }
paths_overlap() {
    local first=${1%/} second=${2%/}
    [[ "$first" == "$second" || "$first" == "$second/"* || "$second" == "$first/"* ]]
}
version_at_least() {
    local actual=$1 required=$2
    [[ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n1)" == "$required" ]]
}
safe_remove_path() {
    local path=${1:-} label=${2:-path}
    [[ -n "$path" && "$path" != "/" && "$path" != "$ROOT_DIR" && "$path" != "${HOME:-/__no_home__}" ]] \
        || die "Refusing to remove unsafe $label: '$path'"
    if [[ "$ALLOW_EXTERNAL_DIRS" == "0" && "$path" != "$ROOT_DIR/"* ]]; then
        die "Refusing to remove external $label while ALLOW_EXTERNAL_DIRS=0: $path"
    fi
}

validate_common_config() {
    local name
    for name in GGML_NATIVE ENABLE_LTO ENABLE_CCACHE ENABLE_OPENMP ENABLE_CPU_REPACK \
                ENABLE_LLAMAFILE ENABLE_FAST_MATH ENABLE_BLAS ENABLE_CUDA ENABLE_CUDA_FA \
                ENABLE_CUDA_FA_ALL_QUANTS ENABLE_CUDA_GRAPHS ENABLE_CUDA_NCCL \
                CUDA_FORCE_MMQ CUDA_FORCE_CUBLAS ENABLE_HIP ENABLE_HIP_GRAPHS ENABLE_HIP_RCCL \
                ENABLE_VULKAN ENABLE_SYCL ENABLE_SYCL_F16 ENABLE_OPENCL ENABLE_OPENVINO \
                ENABLE_RPC ENABLE_SERVER_UI USE_PREBUILT_UI ENABLE_OPENSSL ENABLE_LLGUIDANCE \
                STRIP_BINARIES OFFLINE SOURCE_UPDATE FORCE_SOURCE_RESET ALLOW_EXTERNAL_DIRS \
                DOWNLOAD_MMPROJ VERIFY_REMOTE_SHA256 STRICT_CHECKSUM STRICT_RESOURCES FORCE_DOWNLOAD \
                ENABLE_USER_SERVICE SERVICE_AUTOSTART SERVICE_START_NOW SERVER_KEEP_MODEL_LOADED \
                SERVER_PIN_MODEL SERVER_FULL_GPU_OFFLOAD SERVER_CONT_BATCHING SERVER_METRICS \
                SERVER_EMBEDDINGS SERVER_RERANKING SERVER_JINJA; do
        validate_bool "$name"
    done

    [[ -n "$LLAMA_CPP_REPO" ]] || die "LLAMA_CPP_REPO cannot be empty"
    [[ -n "$LLAMA_CPP_REF" ]] || die "LLAMA_CPP_REF cannot be empty"
    [[ -n "$BLAS_VENDOR" ]] || die "BLAS_VENDOR cannot be empty"
    [[ -n "$BUILD_TARGETS" ]] || die "BUILD_TARGETS cannot be empty"
    [[ "$BUILD_TARGETS" =~ ^[A-Za-z0-9_.+/-]+([[:space:]]+[A-Za-z0-9_.+/-]+)*$ ]] \
        || die "BUILD_TARGETS contains unsupported characters"

    local primary_backends=$((ENABLE_CUDA + ENABLE_HIP + ENABLE_VULKAN + ENABLE_SYCL + ENABLE_OPENCL))
    (( primary_backends <= 1 )) || die "Enable at most one primary GPU backend among CUDA, HIP, Vulkan, SYCL, and OpenCL"
    [[ "$CUDA_FORCE_MMQ" != "1" || "$CUDA_FORCE_CUBLAS" != "1" ]] \
        || die "CUDA_FORCE_MMQ and CUDA_FORCE_CUBLAS are mutually exclusive"
    [[ "$ENABLE_SYCL_F16" != "1" || "$ENABLE_SYCL" == "1" ]] \
        || die "ENABLE_SYCL_F16=1 requires ENABLE_SYCL=1"
    [[ "$ENABLE_CUDA_FA_ALL_QUANTS" != "1" || "$ENABLE_CUDA_FA" == "1" ]] \
        || die "ENABLE_CUDA_FA_ALL_QUANTS=1 requires ENABLE_CUDA_FA=1"
    [[ "$USE_PREBUILT_UI" != "1" || "$ENABLE_SERVER_UI" == "1" ]] \
        || die "USE_PREBUILT_UI=1 requires ENABLE_SERVER_UI=1"

    validate_uint DOWNLOAD_RETRIES
    validate_uint DOWNLOAD_CONNECT_TIMEOUT 0
    validate_uint CTX_SIZE 0
    case "$GPU_LAYERS" in auto|all|none) ;; *) [[ "$GPU_LAYERS" =~ ^[0-9]+$ ]] || die "GPU_LAYERS must be auto, all, none, or an integer" ;; esac
    resolve_threads "$RUNTIME_THREADS" >/dev/null
    resolve_threads "$RUNTIME_THREADS_BATCH" logical >/dev/null

    local label path
    for label in SOURCE_DIR BUILD_DIR OUTPUT_DIR MODEL_DIR; do
        case "$label" in
            SOURCE_DIR) path="$SOURCE_DIR_ABS" ;;
            BUILD_DIR)  path="$BUILD_DIR_ABS" ;;
            OUTPUT_DIR) path="$OUTPUT_DIR_ABS" ;;
            MODEL_DIR)  path="$MODEL_DIR_ABS" ;;
        esac
        [[ -n "$path" && "$path" != "/" && "$path" != "$ROOT_DIR" ]] || die "$label resolves to an unsafe path: $path"
        if [[ "$ALLOW_EXTERNAL_DIRS" == "0" && "$path" != "$ROOT_DIR/"* ]]; then
            die "$label must remain under ROOT_DIR unless ALLOW_EXTERNAL_DIRS=1: $path"
        fi
    done

    paths_overlap "$SOURCE_DIR_ABS" "$BUILD_DIR_ABS" && die "SOURCE_DIR and BUILD_DIR must not overlap"
    paths_overlap "$SOURCE_DIR_ABS" "$OUTPUT_DIR_ABS" && die "SOURCE_DIR and OUTPUT_DIR must not overlap"
    paths_overlap "$BUILD_DIR_ABS" "$OUTPUT_DIR_ABS" && die "BUILD_DIR and OUTPUT_DIR must not overlap"
    paths_overlap "$SOURCE_DIR_ABS" "$MODEL_DIR_ABS" && die "SOURCE_DIR and MODEL_DIR must not overlap"
    paths_overlap "$BUILD_DIR_ABS" "$MODEL_DIR_ABS" && die "BUILD_DIR and MODEL_DIR must not overlap"
    if paths_overlap "$OUTPUT_DIR_ABS" "$MODEL_DIR_ABS" \
        && [[ "$MODEL_DIR_ABS" != "$OUTPUT_DIR_ABS" && "$MODEL_DIR_ABS" != "$OUTPUT_DIR_ABS/"* ]]; then
        die "When OUTPUT_DIR and MODEL_DIR overlap, MODEL_DIR must be OUTPUT_DIR or its child"
    fi
}

logical_cores() {
    if command -v nproc >/dev/null 2>&1; then nproc; else getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'; fi
}
physical_cores() {
    if command -v lscpu >/dev/null 2>&1; then
        local count logical
        count="$(lscpu -p=CORE,SOCKET 2>/dev/null | awk -F, '!/^#/ {print $1 "," $2}' | sort -u | wc -l | tr -d ' ')"
        logical="$(logical_cores)"
        if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
            (( count > logical )) && count=$logical
            printf '%s\n' "$count"; return
        fi
    fi
    logical_cores
}
build_jobs() {
    if [[ "$BUILD_JOBS" == "auto" || -z "$BUILD_JOBS" ]]; then logical_cores
    elif [[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then printf '%s\n' "$BUILD_JOBS"
    else die "BUILD_JOBS must be 'auto' or a positive integer"; fi
}
resolve_threads() {
    local value=${1:-auto} mode=${2:-physical}
    if [[ "$value" == "auto" || -z "$value" ]]; then
        [[ "$mode" == "logical" ]] && logical_cores || physical_cores
    elif [[ "$value" =~ ^[1-9][0-9]*$ ]]; then printf '%s\n' "$value"
    else die "Thread count must be 'auto' or a positive integer, got: $value"; fi
}

selected_cxx() {
    if [[ -n "$CMAKE_CXX_COMPILER" ]]; then printf '%s\n' "$CMAKE_CXX_COMPILER"
    elif [[ "$ENABLE_SYCL" == "1" ]] && command -v icpx >/dev/null 2>&1; then command -v icpx
    else command -v c++ 2>/dev/null || printf 'c++\n'; fi
}
selected_cc() {
    if [[ -n "$CMAKE_C_COMPILER" ]]; then printf '%s\n' "$CMAKE_C_COMPILER"
    elif [[ "$ENABLE_SYCL" == "1" ]] && command -v icx >/dev/null 2>&1; then command -v icx
    else command -v cc 2>/dev/null || printf 'cc\n'; fi
}
native_flags() {
    case "$(uname -m)" in
        x86_64|amd64|i?86) printf '%s\n' '-march=native -mtune=native' ;;
        aarch64|arm64|armv7l|armv8l) printf '%s\n' '-mcpu=native' ;;
        ppc64|ppc64le) printf '%s\n' '-mcpu=native -mtune=native' ;;
        riscv64) printf '%s\n' '-march=native -mtune=native' ;;
        *) printf '\n' ;;
    esac
}
effective_native_flags() { [[ "$GGML_NATIVE" == "1" ]] && native_flags || printf '\n'; }
fast_math_flags() {
    [[ "$ENABLE_FAST_MATH" == "1" ]] && printf '%s\n' '-ffast-math -fno-math-errno -fno-trapping-math' || printf '\n'
}
effective_release_flags() {
    local extra=${1:-} flags='-O3 -DNDEBUG' value
    value="$(effective_native_flags)"; [[ -n "$value" ]] && flags+=" $value"
    value="$(fast_math_flags)"; [[ -n "$value" ]] && flags+=" $value"
    [[ -n "$extra" ]] && flags+=" $extra"
    printf '%s\n' "$flags"
}
effective_c_flags() { effective_release_flags "$EXTRA_C_FLAGS"; }
effective_cxx_flags() { effective_release_flags "$EXTRA_CXX_FLAGS"; }
choose_generator() {
    if [[ "$BUILDER_CMAKE_GENERATOR" == "auto" || -z "$BUILDER_CMAKE_GENERATOR" ]]; then
        command -v ninja >/dev/null 2>&1 && printf 'Ninja\n' || printf 'Unix Makefiles\n'
    else printf '%s\n' "$BUILDER_CMAKE_GENERATOR"; fi
}
canonical_command() {
    local value=${1:-} path
    [[ -n "$value" ]] || return 1
    path="$(command -v -- "$value" 2>/dev/null || true)"; [[ -n "$path" ]] || return 1
    command -v realpath >/dev/null 2>&1 && realpath -e -- "$path" 2>/dev/null || printf '%s\n' "$path"
}
detect_cuda_archs() {
    if [[ "$CUDA_ARCHS" != "auto" && -n "$CUDA_ARCHS" ]]; then printf '%s\n' "$CUDA_ARCHS"; return; fi
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null \
        | tr -d ' ' | sed 's/\.//g' | awk 'NF && !seen[$0]++' | paste -sd';' -
}
detect_amd_targets() {
    if [[ "$AMDGPU_TARGETS" != "auto" && -n "$AMDGPU_TARGETS" ]]; then printf '%s\n' "$AMDGPU_TARGETS"; return; fi
    if command -v rocm_agent_enumerator >/dev/null 2>&1; then
        rocm_agent_enumerator 2>/dev/null | grep -E '^gfx[0-9a-f]+' | awk '!seen[$0]++' | paste -sd';' -; return
    fi
    if command -v rocminfo >/dev/null 2>&1; then
        rocminfo 2>/dev/null | awk '/^[[:space:]]*Name:[[:space:]]+gfx/ {print $2}' | awk '!seen[$0]++' | paste -sd';' -; return
    fi
    return 1
}

format_params_b() {
    local value=$1
    [[ "$value" == "-" ]] && { printf -- '-'; return; }
    awk -v value="$value" 'BEGIN { if (value < 1) printf "%.0fM", value*1000; else if (value == int(value)) printf "%dB", value; else printf "%.1fB", value }'
}
format_mib() {
    local mib=$1
    awk -v mib="$mib" 'BEGIN { if (mib >= 1024) printf "%.1fG", mib/1024; else printf "%dM", mib }'
}
total_ram_gib() { awk '/MemTotal:/ {printf "%d\n", $2/1024/1024; exit}' /proc/meminfo 2>/dev/null || printf '0\n'; }
available_ram_gib() { awk '/MemAvailable:/ {printf "%d\n", $2/1024/1024; exit}' /proc/meminfo 2>/dev/null || total_ram_gib; }
accelerator_label() {
    if [[ "$ENABLE_CUDA" == "1" ]]; then printf 'CUDA'
    elif [[ "$ENABLE_HIP" == "1" ]]; then printf 'HIP/ROCm'
    elif [[ "$ENABLE_VULKAN" == "1" ]]; then printf 'Vulkan'
    elif [[ "$ENABLE_SYCL" == "1" ]]; then printf 'SYCL'
    elif [[ "$ENABLE_OPENCL" == "1" ]]; then printf 'OpenCL'
    else printf 'CPU'; fi
}

model_id_valid() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; }
slugify() {
    local value=${1:-}
    value="${value,,}"
    value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9._+-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
    [[ -n "$value" ]] || value=custom-model
    printf '%s\n' "$value"
}
gguf_magic_ok() {
    local path=$1 magic
    [[ -f "$path" ]] || return 1
    magic="$(od -An -N4 -tx1 "$path" 2>/dev/null | tr -d '[:space:]')"
    [[ "$magic" == "47475546" ]]
}
validate_hf_token() {
    [[ -z "$HF_TOKEN" ]] && return 0
    [[ "$HF_TOKEN" =~ ^[A-Za-z0-9._-]+$ ]] || die "HF_TOKEN contains unsupported characters; use an ordinary Hugging Face access token"
}
urlencode_path() {
    local value=$1
    require_cmd python3
    python3 - "$value" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe="/"))
PY
}


urlencode_component() {
    local value=$1
    require_cmd python3
    python3 - "$value" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

validate_service_config() {
    validate_common_config
    [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "SERVICE_NAME contains unsupported characters"
    [[ "$SERVICE_RESTART" =~ ^(no|on-success|on-failure|on-abnormal|on-abort|on-watchdog|always)$ ]] \
        || die "Unsupported SERVICE_RESTART value: $SERVICE_RESTART"
    validate_uint SERVICE_RESTART_SEC
    validate_uint SERVICE_TIMEOUT_STOP_SEC 0
    validate_uint SERVER_PORT 0; (( SERVER_PORT <= 65535 )) || die "SERVER_PORT must be <= 65535"
    validate_uint SERVER_CTX_SIZE 0
    validate_uint SERVER_PARALLEL 0
    validate_uint SERVER_TIMEOUT 0
    [[ "$SERVER_SLEEP_IDLE_SECONDS" =~ ^-1$|^[0-9]+$ ]] || die "SERVER_SLEEP_IDLE_SECONDS must be -1 or a non-negative integer"
    [[ -n "$SERVER_HOST" && "$SERVER_HOST" != *[[:space:]]* ]] || die "SERVER_HOST is invalid"
    [[ -n "$SERVER_ALIAS" && "$SERVER_ALIAS" != *$'\n'* ]] || die "SERVER_ALIAS is invalid"
    case "$SERVER_FLASH_ATTN" in auto|on|off) ;; *) die "SERVER_FLASH_ATTN must be auto, on, or off" ;; esac
    case "$SERVER_LOAD_MODE" in none|mmap|mlock|mmap+mlock|dio) ;; *) die "Unsupported SERVER_LOAD_MODE: $SERVER_LOAD_MODE" ;; esac
    case "$SERVER_GPU_LAYERS" in auto|all|none) ;; *) [[ "$SERVER_GPU_LAYERS" =~ ^[0-9]+$ ]] || die "SERVER_GPU_LAYERS must be auto, all, none, or an integer" ;; esac
    case "$SERVER_CACHE_TYPE_K" in f32|f16|bf16|q8_0|q4_0|q4_1|iq4_nl|q5_0|q5_1) ;; *) die "Unsupported SERVER_CACHE_TYPE_K: $SERVER_CACHE_TYPE_K" ;; esac
    case "$SERVER_CACHE_TYPE_V" in f32|f16|bf16|q8_0|q4_0|q4_1|iq4_nl|q5_0|q5_1) ;; *) die "Unsupported SERVER_CACHE_TYPE_V: $SERVER_CACHE_TYPE_V" ;; esac
    resolve_threads "$SERVER_THREADS" >/dev/null
    resolve_threads "$SERVER_THREADS_BATCH" logical >/dev/null
    [[ "$SERVER_API_KEY" != *$'\n'* && "$SERVER_API_KEY" != *$'\r'* && "$SERVER_API_KEY" != *$'\t'* ]] \
        || die "SERVER_API_KEY contains unsupported control characters"
    [[ "$SERVER_EXTRA_ARGS" != *$'\n'* && "$SERVER_EXTRA_ARGS" != *$'\r'* ]] \
        || die "SERVER_EXTRA_ARGS must be a single line"
}
