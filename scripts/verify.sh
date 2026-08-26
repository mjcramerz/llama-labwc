#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
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

[[ -s "$OUTPUT_DIR_ABS/metadata/build-info.txt" ]] || die "Missing build metadata"
info "Verified ${#targets[@]} staged llama.cpp executable(s)"
