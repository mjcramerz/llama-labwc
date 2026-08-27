#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
require_cmd sha256sum
[[ -f "$OUTPUT_DIR_ABS/.native-builder-output" ]] || die "Output is not staged; run make build"
read -r -a targets <<<"$BUILD_TARGETS"

for target in "${targets[@]}"; do
    binary="$OUTPUT_DIR_ABS/bin/$target"
    [[ -x "$binary" ]] || die "Missing staged executable: $binary"
    [[ ! -L "$binary" ]] || die "Staged binary unexpectedly is a symlink: $binary"
    size="$(stat -c %s "$binary")"
    (( size > 4096 )) || die "$target is implausibly small ($size bytes)"
    if command -v ldd >/dev/null 2>&1; then
        ldd_output="$(ldd "$binary" 2>&1 || true)"
        if grep -q 'not found' <<<"$ldd_output"; then
            printf '%s\n' "$ldd_output" >&2
            die "$target has unresolved dynamic dependencies"
        fi
    fi
done

for target in llama-cli llama-server; do
    binary="$OUTPUT_DIR_ABS/bin/$target"
    [[ -x "$binary" ]] || continue
    if ! "$binary" --version >"$OUTPUT_DIR_ABS/metadata/${target}-version.txt" 2>&1; then
        cat "$OUTPUT_DIR_ABS/metadata/${target}-version.txt" >&2 || true
        die "$target could not execute on this host"
    fi
done

if [[ "$USE_PREBUILT_UI" == "1" ]]; then
    ui_bundle_dir="$OUTPUT_DIR_ABS/share/llama-ui"
    for ui_name in dist.tar.gz SHA256SUMS bundle-info.txt; do
        ui_path="$ui_bundle_dir/$ui_name"
        [[ -f "$ui_path" && -s "$ui_path" ]] || die "Missing staged pinned UI artifact: $ui_path"
        [[ ! -L "$ui_path" ]] || die "Staged pinned UI artifact unexpectedly is a symlink: $ui_path"
    done
    (
        cd -- "$ui_bundle_dir"
        sha256sum --check --strict SHA256SUMS >/dev/null
    ) || die "Staged pinned UI bundle failed its local checksum manifest"
    staged_ui_sha256="$(sha256sum "$ui_bundle_dir/dist.tar.gz" | awk '{print $1}')"
    [[ "$staged_ui_sha256" == "$SERVER_UI_SHA256" ]] \
        || die "Staged pinned UI bundle does not match SERVER_UI_SHA256"
    bundle_value() {
        sed -n "s/^${1}=//p" "$ui_bundle_dir/bundle-info.txt" | tail -n1
    }
    [[ "$(bundle_value format)" == "llama-ui-prebuilt-v1" ]] \
        || die "Staged pinned UI bundle has an unsupported provenance format"
    [[ "$(bundle_value bucket)" == "$SERVER_UI_HF_BUCKET" ]] \
        || die "Staged pinned UI bundle bucket does not match SERVER_UI_HF_BUCKET"
    [[ "$(bundle_value version)" == "$SERVER_UI_VERSION" ]] \
        || die "Staged pinned UI bundle version does not match SERVER_UI_VERSION"
    [[ "$(bundle_value sha256)" == "$SERVER_UI_SHA256" ]] \
        || die "Staged pinned UI bundle provenance checksum does not match SERVER_UI_SHA256"
    [[ "$(bundle_value embedded_in)" == "llama-server" ]] \
        || die "Staged pinned UI bundle provenance does not identify llama-server"
fi

checksums="$OUTPUT_DIR_ABS/metadata/SHA256SUMS"
[[ -s "$checksums" ]] || die "Missing staged checksum manifest: $checksums"
(
    cd -- "$OUTPUT_DIR_ABS"
    sha256sum --check --strict metadata/SHA256SUMS
)

metadata="$OUTPUT_DIR_ABS/metadata/build-info.txt"
[[ -s "$metadata" ]] || die "Missing build metadata"
metadata_value() {
    sed -n "s/^${1}=//p" "$metadata" | tail -n1
}
metadata_profile="$(metadata_value build_profile)"
[[ "$metadata_profile" == "$BUILD_PROFILE" ]] \
    || die "Staged metadata profile '$metadata_profile' does not match requested profile '$BUILD_PROFILE'"
metadata_server_ui="$(metadata_value server_ui)"
metadata_server_ui_prebuilt="$(metadata_value server_ui_prebuilt)"
[[ "$metadata_server_ui" == "$ENABLE_SERVER_UI" ]] \
    || die "Staged server UI setting '$metadata_server_ui' does not match requested setting '$ENABLE_SERVER_UI'"
[[ "$metadata_server_ui_prebuilt" == "$USE_PREBUILT_UI" ]] \
    || die "Staged prebuilt UI setting '$metadata_server_ui_prebuilt' does not match requested setting '$USE_PREBUILT_UI'"
if [[ "$USE_PREBUILT_UI" == "1" ]]; then
    [[ "$(metadata_value server_ui_hf_bucket)" == "$SERVER_UI_HF_BUCKET" ]] \
        || die "Staged server UI bucket does not match SERVER_UI_HF_BUCKET"
    [[ "$(metadata_value server_ui_requested_version)" == "$SERVER_UI_VERSION" ]] \
        || die "Staged server UI version does not match SERVER_UI_VERSION"
    [[ "$(metadata_value server_ui_expected_sha256)" == "$SERVER_UI_SHA256" ]] \
        || die "Staged server UI checksum does not match SERVER_UI_SHA256"
    [[ "$(metadata_value server_ui_asset_source)" == "prebuilt-hf" ]] \
        || die "Staged server UI was not built from the pinned prebuilt bundle"
    [[ "$(metadata_value server_ui_asset_version)" == "$SERVER_UI_VERSION" ]] \
        || die "Resolved server UI version does not match SERVER_UI_VERSION"
    [[ "$(metadata_value server_ui_asset_sha256)" == "$SERVER_UI_SHA256" ]] \
        || die "Resolved server UI archive does not match SERVER_UI_SHA256"
fi
info "Verified ${#targets[@]} staged llama.cpp executable(s)"
