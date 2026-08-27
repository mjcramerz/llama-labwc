#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
for command_name in cmake install sha256sum git find; do require_cmd "$command_name"; done
prepare_sccache_dir
prepare_cuda_glibc_compat
cmake_path="$(canonical_command cmake || true)"
[[ -n "$cmake_path" ]] || die "Could not resolve the CMake executable"
[[ -f "$BUILD_DIR_ABS/CMakeCache.txt" ]] || die "Build is not configured; run make configure"
[[ -f "$BUILD_DIR_ABS/.native-builder-build" ]] || die "Refusing unmarked build directory: $BUILD_DIR_ABS"

read -r -a targets <<<"$BUILD_TARGETS"
((${#targets[@]} > 0)) || die "No BUILD_TARGETS were configured"
jobs="$(build_jobs)"
log "Building ${targets[*]} with $jobs parallel job(s)"
"$cmake_path" --build "$BUILD_DIR_ABS" --config Release --parallel "$jobs" --target "${targets[@]}"
verify_server_ui_assets

output_marker="$OUTPUT_DIR_ABS/.native-builder-output"
if [[ -e "$OUTPUT_DIR_ABS" && ! -d "$OUTPUT_DIR_ABS" ]]; then
    die "OUTPUT_DIR exists but is not a directory: $OUTPUT_DIR_ABS"
fi
if [[ -d "$OUTPUT_DIR_ABS" && ! -f "$output_marker" ]] \
    && [[ -n "$(find "$OUTPUT_DIR_ABS" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "Refusing to stage into an unmarked non-empty OUTPUT_DIR: $OUTPUT_DIR_ABS"
fi
mkdir -p "$OUTPUT_DIR_ABS/bin" "$OUTPUT_DIR_ABS/metadata" "$OUTPUT_DIR_ABS/share"
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

ui_bundle_files=()
ui_bundle_dir="$OUTPUT_DIR_ABS/share/llama-ui"
if [[ "$USE_PREBUILT_UI" == "1" ]]; then
    ui_bundle_source="$BUILD_DIR_ABS/tools/ui/dist.tar.gz"
    [[ -s "$ui_bundle_source" ]] \
        || die "Verified prebuilt UI archive is unavailable for staging: $ui_bundle_source"
    mkdir -p -- "$ui_bundle_dir"

    ui_archive_tmp="$ui_bundle_dir/.dist.tar.gz.tmp.$$"
    ui_checksums_tmp="$ui_bundle_dir/.SHA256SUMS.tmp.$$"
    ui_info_tmp="$ui_bundle_dir/.bundle-info.txt.tmp.$$"
    install -m 0644 "$ui_bundle_source" "$ui_archive_tmp"
    printf '%s  dist.tar.gz\n' "$SERVER_UI_ASSET_SHA256" >"$ui_checksums_tmp"
    {
        printf 'format=llama-ui-prebuilt-v1\n'
        printf 'bucket=%s\n' "$SERVER_UI_HF_BUCKET"
        printf 'version=%s\n' "$SERVER_UI_ASSET_VERSION"
        printf 'sha256=%s\n' "$SERVER_UI_ASSET_SHA256"
        printf 'source_url=https://huggingface.co/buckets/%s/resolve/%s/dist.tar.gz\n' \
            "$SERVER_UI_HF_BUCKET" "$SERVER_UI_ASSET_VERSION"
        printf 'embedded_in=llama-server\n'
    } >"$ui_info_tmp"
    mv -f -- "$ui_archive_tmp" "$ui_bundle_dir/dist.tar.gz"
    mv -f -- "$ui_checksums_tmp" "$ui_bundle_dir/SHA256SUMS"
    mv -f -- "$ui_info_tmp" "$ui_bundle_dir/bundle-info.txt"
    (
        cd -- "$ui_bundle_dir"
        sha256sum --check --strict SHA256SUMS >/dev/null
    )
    ui_bundle_files=(
        share/llama-ui/dist.tar.gz
        share/llama-ui/SHA256SUMS
        share/llama-ui/bundle-info.txt
    )
    info "Staged pinned UI bundle: $ui_bundle_dir/dist.tar.gz"
else
    rm -f -- \
        "$ui_bundle_dir/dist.tar.gz" \
        "$ui_bundle_dir/SHA256SUMS" \
        "$ui_bundle_dir/bundle-info.txt"
fi

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
    printf 'build_profile=%s\n' "$BUILD_PROFILE"
    printf 'source_repo=%s\n' "$LLAMA_CPP_REPO"
    printf 'source_ref=%s\n' "$LLAMA_CPP_REF"
    printf 'source_commit=%s\n' "$commit"
    printf 'host=%s\n' "$(uname -a)"
    printf 'backend=%s\n' "$(accelerator_label)"
    printf 'build_targets=%s\n' "${staged[*]}"
    printf 'c_flags=%s\n' "$CMAKE_C_FLAGS"
    printf 'cxx_flags=%s\n' "$CMAKE_CXX_FLAGS"
    printf 'cuda_flags=%s\n' "$CMAKE_CUDA_FLAGS"
    printf 'c_flags_release=%s\n' "$(effective_c_flags)"
    printf 'cxx_flags_release=%s\n' "$(effective_cxx_flags)"
    printf 'cuda_flags_release=%s\n' "$(effective_cuda_flags)"
    printf 'c_compiler=%s\n' "$($cc_path --version 2>/dev/null | head -n1)"
    printf 'cxx_compiler=%s\n' "$($cxx_path --version 2>/dev/null | head -n1)"
    if [[ "$ENABLE_CUDA" == "1" ]]; then
        cuda="$(selected_cuda)"
        cuda_path="$(canonical_command "$cuda" || printf '%s' "$cuda")"
        cuda_host="$(selected_cuda_host)"
        cuda_host_path="$(canonical_command "$cuda_host" || printf '%s' "$cuda_host")"
        printf 'cuda_compiler=%s\n' "$($cuda_path --version 2>/dev/null | tail -n1)"
        printf 'cuda_host_compiler=%s\n' "$($cuda_host_path --version 2>/dev/null | head -n1)"
    fi
    printf 'cmake=%s\n' "$($cmake_path --version | head -n1)"
    printf 'build_jobs=%s\n' "$jobs"
    printf 'ggml_native=%s\n' "$GGML_NATIVE"
    printf 'lto=%s\n' "$ENABLE_LTO"
    printf 'ccache=%s\n' "$ENABLE_CCACHE"
    printf 'compiler_cache=%s\n' "$(cache_launcher_label)"
    if sccache_enabled || cuda_sccache_enabled; then
        printf 'sccache_dir=%s\n' "$SCCACHE_DIR_ABS"
        printf 'sccache_server_uds=%s\n' "${SCCACHE_SERVER_UDS_ABS:-}"
    fi
    printf 'openmp=%s\n' "$ENABLE_OPENMP"
    printf 'cpu_repack=%s\n' "$ENABLE_CPU_REPACK"
    printf 'llamafile=%s\n' "$ENABLE_LLAMAFILE"
    printf 'fast_math=%s\n' "$ENABLE_FAST_MATH"
    printf 'blas=%s\n' "$ENABLE_BLAS"
    printf 'blas_vendor=%s\n' "$BLAS_VENDOR"
    printf 'cuda=%s\n' "$ENABLE_CUDA"
    printf 'cuda_architectures=%s\n' "$cuda_archs"
    printf 'cuda_flash_attention=%s\n' "$ENABLE_CUDA_FA"
    printf 'cuda_flash_attention_all_quants=%s\n' "$ENABLE_CUDA_FA_ALL_QUANTS"
    printf 'cuda_force_mmq=%s\n' "$CUDA_FORCE_MMQ"
    printf 'cuda_force_cublas=%s\n' "$CUDA_FORCE_CUBLAS"
    printf 'cuda_no_peer_copy=%s\n' "$CUDA_NO_PEER_COPY"
    printf 'cuda_no_vmm=%s\n' "$CUDA_NO_VMM"
    printf 'cuda_graphs=%s\n' "$ENABLE_CUDA_GRAPHS"
    printf 'cuda_nccl=%s\n' "$ENABLE_CUDA_NCCL"
    printf 'cuda_compression_mode=%s\n' "$CUDA_COMPRESSION_MODE"
    printf 'cuda_glibc_compatibility=%s\n' "$ENABLE_CUDA_GLIBC_COMPAT"
    if [[ "$ENABLE_CUDA_GLIBC_COMPAT" == "1" ]]; then
        printf 'cuda_glibc_source_header=%s\n' "$CUDA_GLIBC_HEADER_ABS"
        printf 'cuda_glibc_private_overlay=%s\n' "$CUDA_GLIBC_PATCHED_HEADER_ABS"
    fi
    printf 'hip=%s\n' "$ENABLE_HIP"
    printf 'amdgpu_targets=%s\n' "$amd_targets"
    printf 'vulkan=%s\n' "$ENABLE_VULKAN"
    printf 'sycl=%s\n' "$ENABLE_SYCL"
    printf 'opencl=%s\n' "$ENABLE_OPENCL"
    printf 'openvino=%s\n' "$ENABLE_OPENVINO"
    printf 'rpc=%s\n' "$ENABLE_RPC"
    printf 'server_ui=%s\n' "$ENABLE_SERVER_UI"
    printf 'server_ui_prebuilt=%s\n' "$USE_PREBUILT_UI"
    printf 'server_ui_gzip=%s\n' "$ENABLE_SERVER_UI_GZIP"
    printf 'server_ui_hf_bucket=%s\n' "$SERVER_UI_HF_BUCKET"
    printf 'server_ui_requested_version=%s\n' "${SERVER_UI_VERSION:-disabled}"
    printf 'server_ui_expected_sha256=%s\n' "${SERVER_UI_SHA256:-disabled}"
    printf 'server_ui_asset_source=%s\n' "$SERVER_UI_ASSET_SOURCE"
    printf 'server_ui_asset_version=%s\n' "$SERVER_UI_ASSET_VERSION"
    printf 'server_ui_asset_sha256=%s\n' "$SERVER_UI_ASSET_SHA256"
    for target in "${staged[@]}"; do
        printf 'sha256_%s=%s\n' "$target" "$(sha256sum "$OUTPUT_DIR_ABS/bin/$target" | awk '{print $1}')"
    done
} >"$OUTPUT_DIR_ABS/metadata/build-info.txt"

checksums_tmp="$OUTPUT_DIR_ABS/metadata/.SHA256SUMS.tmp.$$"
: >"$checksums_tmp"
checksum_paths=()
for target in "${staged[@]}"; do
    checksum_paths+=("bin/$target")
done
checksum_paths+=("${ui_bundle_files[@]}")
for checksum_path in "${checksum_paths[@]}"; do
    (
        cd -- "$OUTPUT_DIR_ABS"
        sha256sum "$checksum_path"
    ) >>"$checksums_tmp"
done
mv -f -- "$checksums_tmp" "$OUTPUT_DIR_ABS/metadata/SHA256SUMS"

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
