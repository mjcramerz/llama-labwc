#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
for command_name in cmake install sha256sum git find; do require_cmd "$command_name"; done
[[ -f "$BUILD_DIR_ABS/CMakeCache.txt" ]] || die "Build is not configured; run make configure"
[[ -f "$BUILD_DIR_ABS/.native-builder-build" ]] || die "Refusing unmarked build directory: $BUILD_DIR_ABS"

read -r -a targets <<<"$BUILD_TARGETS"
((${#targets[@]} > 0)) || die "No BUILD_TARGETS were configured"
jobs="$(build_jobs)"
log "Building ${targets[*]} with $jobs parallel job(s)"
cmake --build "$BUILD_DIR_ABS" --config Release --parallel "$jobs" --target "${targets[@]}"

output_marker="$OUTPUT_DIR_ABS/.native-builder-output"
if [[ -e "$OUTPUT_DIR_ABS" && ! -d "$OUTPUT_DIR_ABS" ]]; then
    die "OUTPUT_DIR exists but is not a directory: $OUTPUT_DIR_ABS"
fi
if [[ -d "$OUTPUT_DIR_ABS" && ! -f "$output_marker" ]] \
    && [[ -n "$(find "$OUTPUT_DIR_ABS" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "Refusing to stage into an unmarked non-empty OUTPUT_DIR: $OUTPUT_DIR_ABS"
fi
mkdir -p "$OUTPUT_DIR_ABS/bin" "$OUTPUT_DIR_ABS/metadata"
printf 'native llama.cpp output directory\nroot=%s\n' "$ROOT_DIR" >"$output_marker"

find_binary() {
    local target=$1 candidate
    for candidate in \
        "$BUILD_DIR_ABS/bin/$target" \
        "$BUILD_DIR_ABS/bin/Release/$target" \
        "$BUILD_DIR_ABS/Release/$target"; do
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    candidate="$(find "$BUILD_DIR_ABS" -maxdepth 4 -type f -name "$target" -perm -u+x -print -quit 2>/dev/null || true)"
    [[ -n "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    return 1
}

staged=()
for target in "${targets[@]}"; do
    binary="$(find_binary "$target" || true)"
    [[ -n "$binary" ]] || die "Target '$target' built, but its executable was not found under $BUILD_DIR_ABS"
    tmp_binary="$OUTPUT_DIR_ABS/bin/.$target.tmp.$$"
    install -m 0755 "$binary" "$tmp_binary"
    if [[ "$STRIP_BINARIES" == "1" ]] && command -v strip >/dev/null 2>&1; then
        strip --strip-unneeded "$tmp_binary" 2>/dev/null || warn "strip could not process $target; keeping symbols"
    fi
    mv -f -- "$tmp_binary" "$OUTPUT_DIR_ABS/bin/$target"
    ln -sfn "bin/$target" "$OUTPUT_DIR_ABS/$target"
    staged+=("$target")
done

if [[ -f "$SOURCE_DIR_ABS/LICENSE" ]]; then
    install -m 0644 "$SOURCE_DIR_ABS/LICENSE" "$OUTPUT_DIR_ABS/metadata/LLAMA_CPP_LICENSE"
fi
[[ -f "$BUILD_DIR_ABS/compile_commands.json" ]] \
    && cp -f "$BUILD_DIR_ABS/compile_commands.json" "$OUTPUT_DIR_ABS/metadata/compile_commands.json"
[[ -f "$BUILD_DIR_ABS/cmake-command.txt" ]] \
    && cp -f "$BUILD_DIR_ABS/cmake-command.txt" "$OUTPUT_DIR_ABS/metadata/cmake-command.txt"

commit="$(git -C "$SOURCE_DIR_ABS" rev-parse HEAD 2>/dev/null || printf unknown)"
cc="$(selected_cc)"; cxx="$(selected_cxx)"
cc_path="$(canonical_command "$cc" || printf '%s' "$cc")"
cxx_path="$(canonical_command "$cxx" || printf '%s' "$cxx")"
cuda_archs=disabled; amd_targets=disabled
[[ "$ENABLE_CUDA" == "1" ]] && cuda_archs="$(detect_cuda_archs || printf unknown)"
[[ "$ENABLE_HIP" == "1" ]] && amd_targets="$(detect_amd_targets || printf unknown)"

{
    printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source_repo=%s\n' "$LLAMA_CPP_REPO"
    printf 'source_ref=%s\n' "$LLAMA_CPP_REF"
    printf 'source_commit=%s\n' "$commit"
    printf 'host=%s\n' "$(uname -a)"
    printf 'backend=%s\n' "$(accelerator_label)"
    printf 'build_targets=%s\n' "${staged[*]}"
    printf 'c_flags_release=%s\n' "$(effective_c_flags)"
    printf 'cxx_flags_release=%s\n' "$(effective_cxx_flags)"
    printf 'c_compiler=%s\n' "$($cc_path --version 2>/dev/null | head -n1)"
    printf 'cxx_compiler=%s\n' "$($cxx_path --version 2>/dev/null | head -n1)"
    printf 'cmake=%s\n' "$(cmake --version | head -n1)"
    printf 'build_jobs=%s\n' "$jobs"
    printf 'ggml_native=%s\n' "$GGML_NATIVE"
    printf 'lto=%s\n' "$ENABLE_LTO"
    printf 'ccache=%s\n' "$ENABLE_CCACHE"
    printf 'openmp=%s\n' "$ENABLE_OPENMP"
    printf 'cpu_repack=%s\n' "$ENABLE_CPU_REPACK"
    printf 'llamafile=%s\n' "$ENABLE_LLAMAFILE"
    printf 'fast_math=%s\n' "$ENABLE_FAST_MATH"
    printf 'blas=%s\n' "$ENABLE_BLAS"
    printf 'blas_vendor=%s\n' "$BLAS_VENDOR"
    printf 'cuda=%s\n' "$ENABLE_CUDA"
    printf 'cuda_architectures=%s\n' "$cuda_archs"
    printf 'hip=%s\n' "$ENABLE_HIP"
    printf 'amdgpu_targets=%s\n' "$amd_targets"
    printf 'vulkan=%s\n' "$ENABLE_VULKAN"
    printf 'sycl=%s\n' "$ENABLE_SYCL"
    printf 'opencl=%s\n' "$ENABLE_OPENCL"
    printf 'openvino=%s\n' "$ENABLE_OPENVINO"
    printf 'rpc=%s\n' "$ENABLE_RPC"
    printf 'server_ui=%s\n' "$ENABLE_SERVER_UI"
    for target in "${staged[@]}"; do
        printf 'sha256_%s=%s\n' "$target" "$(sha256sum "$OUTPUT_DIR_ABS/bin/$target" | awk '{print $1}')"
    done
} >"$OUTPUT_DIR_ABS/metadata/build-info.txt"

: >"$OUTPUT_DIR_ABS/metadata/file.txt"
: >"$OUTPUT_DIR_ABS/metadata/ldd.txt"
for target in "${staged[@]}"; do
    command -v file >/dev/null 2>&1 && file "$OUTPUT_DIR_ABS/bin/$target" >>"$OUTPUT_DIR_ABS/metadata/file.txt"
    if command -v ldd >/dev/null 2>&1; then
        printf '\n[%s]\n' "$target" >>"$OUTPUT_DIR_ABS/metadata/ldd.txt"
        ldd "$OUTPUT_DIR_ABS/bin/$target" >>"$OUTPUT_DIR_ABS/metadata/ldd.txt" 2>&1 || true
    fi
done

info "Staged binaries: ${staged[*]}"
info "Output directory: $OUTPUT_DIR_ABS/bin"
