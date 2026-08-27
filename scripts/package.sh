#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
for command_name in tar gzip install sha256sum mktemp grep; do
    require_cmd "$command_name"
done

[[ -n "$ARCHIVE_PATH_ABS" ]] || die "ARCHIVE_PATH is required for packaging"
[[ -f "$OUTPUT_DIR_ABS/.native-builder-output" ]] \
    || die "OUTPUT_DIR is not marked as managed: $OUTPUT_DIR_ABS"

read -r -a targets <<<"$BUILD_TARGETS"
((${#targets[@]} > 0)) || die "No executable targets are configured"
for target in "${targets[@]}"; do
    [[ -x "$OUTPUT_DIR_ABS/bin/$target" ]] \
        || die "Cannot package missing staged binary: $OUTPUT_DIR_ABS/bin/$target"
done

archive_dir="$(dirname -- "$ARCHIVE_PATH_ABS")"
archive_name="$(basename -- "$ARCHIVE_PATH_ABS")"
[[ "$archive_dir" != "/" ]] || die "Refusing to write an archive directly under /"
if [[ -e "$ARCHIVE_PATH_ABS" && ! -f "$ARCHIVE_PATH_ABS" ]]; then
    die "ARCHIVE_PATH exists but is not a regular file: $ARCHIVE_PATH_ABS"
fi
mkdir -p -- "$archive_dir"
[[ -d "$archive_dir" && -w "$archive_dir" ]] \
    || die "Archive directory is not writable: $archive_dir"

stage_dir="$(mktemp -d)"
tmp_archive="$(mktemp "$archive_dir/.${archive_name}.tmp.XXXXXX")"
cleanup() {
    rm -rf -- "$stage_dir"
    rm -f -- "$tmp_archive"
}
trap cleanup EXIT

package_name="llama-$BUILD_PROFILE"
package_root="$stage_dir/$package_name"
mkdir -p -- "$package_root/bin" "$package_root/metadata"
for target in "${targets[@]}"; do
    install -m 0755 "$OUTPUT_DIR_ABS/bin/$target" "$package_root/bin/$target"
done
for metadata_name in \
    SHA256SUMS build-info.txt LLAMA_CPP_LICENSE cmake-command.txt \
    file.txt ldd.txt llama-cli-version.txt llama-server-version.txt; do
    if [[ -f "$OUTPUT_DIR_ABS/metadata/$metadata_name" ]]; then
        install -m 0644 "$OUTPUT_DIR_ABS/metadata/$metadata_name" \
            "$package_root/metadata/$metadata_name"
    fi
done
if [[ "$USE_PREBUILT_UI" == "1" ]]; then
    mkdir -p -- "$package_root/share/llama-ui"
    for ui_name in dist.tar.gz SHA256SUMS bundle-info.txt; do
        ui_source="$OUTPUT_DIR_ABS/share/llama-ui/$ui_name"
        [[ -f "$ui_source" && -s "$ui_source" ]] \
            || die "Cannot package missing pinned UI artifact: $ui_source"
        install -m 0644 "$ui_source" "$package_root/share/llama-ui/$ui_name"
    done
fi

(
    cd -- "$package_root"
    sha256sum --check --strict metadata/SHA256SUMS >/dev/null
)

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$stage_dir" -cf - "$package_name" | gzip -n >"$tmp_archive"
gzip --test "$tmp_archive"

archive_entries="$(tar -tzf "$tmp_archive")"
for target in "${targets[@]}"; do
    grep -Fqx -- "$package_name/bin/$target" <<<"$archive_entries" \
        || die "Packaged archive is missing $target"
done
grep -Fqx -- "$package_name/metadata/SHA256SUMS" <<<"$archive_entries" \
    || die "Packaged archive is missing metadata/SHA256SUMS"
if [[ "$USE_PREBUILT_UI" == "1" ]]; then
    for ui_name in dist.tar.gz SHA256SUMS bundle-info.txt; do
        grep -Fqx -- "$package_name/share/llama-ui/$ui_name" <<<"$archive_entries" \
            || die "Packaged archive is missing share/llama-ui/$ui_name"
    done
fi

mv -f -- "$tmp_archive" "$ARCHIVE_PATH_ABS"
archive_sha="$(sha256sum "$ARCHIVE_PATH_ABS" | awk '{print $1}')"
info "Created archive: $ARCHIVE_PATH_ABS"
info "Archive SHA-256: $archive_sha"
