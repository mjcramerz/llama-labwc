#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
mode=${1:-model}
case "$mode" in model|--model) mode=model ;; --mmproj) mode=mmproj ;; --dir) mode=dir ;; *) die "Usage: model-path.sh [--model|--mmproj|--dir]" ;; esac
selection="${MODEL:-}"

resolve_downloaded_dir() {
    local selected=$1 directory
    if [[ -n "$selected" ]]; then
        model_id_valid "$selected" || return 1
        directory="$MODEL_DIR_ABS/$selected"
        [[ -d "$directory" ]] || return 1
        printf '%s\n' "$directory"
        return 0
    fi
    local -a candidates=()
    while IFS= read -r -d '' directory; do
        candidates+=("$(dirname -- "$directory")")
    done < <(find "$MODEL_DIR_ABS" -mindepth 2 -maxdepth 2 -type f -name model.path -print0 2>/dev/null | sort -z)
    if ((${#candidates[@]} == 1)); then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi
    if ((${#candidates[@]} == 0)); then
        die "No downloaded model was found. Run make download or set MODEL=/path/model.gguf"
    fi
    die "Multiple downloaded models exist; select one with MODEL=<catalog-or-local-id>"
}

if [[ -n "$selection" && -f "$selection" ]]; then
    [[ "$mode" == model ]] || { [[ "$mode" == dir ]] && dirname -- "$(realpath -e -- "$selection")"; exit 0; }
    gguf_magic_ok "$selection" || die "Selected file is not a GGUF model: $selection"
    realpath -e -- "$selection"
    exit 0
fi
if [[ -n "$selection" && "$selection" = /* && ! -f "$selection" ]]; then
    die "Selected model path does not exist: $selection"
fi

[[ -d "$MODEL_DIR_ABS" ]] || die "Model directory does not exist: $MODEL_DIR_ABS"
directory="$(resolve_downloaded_dir "$selection")"
[[ -f "$directory/.native-builder-model" ]] || die "Refusing unmarked model directory: $directory"
if [[ "$mode" == dir ]]; then
    realpath -e -- "$directory"
    exit 0
fi

path_file="$directory/model.path"
[[ -s "$path_file" ]] || die "Model is incomplete; missing $path_file"
if [[ "$mode" == mmproj ]]; then
    path_file="$directory/mmproj.path"
    [[ -s "$path_file" ]] || exit 3
fi
relative="$(head -n1 "$path_file")"
[[ -n "$relative" && "$relative" != /* && "$relative" != *..* ]] || die "Unsafe path in $path_file"
resolved="$directory/$relative"
[[ -f "$resolved" ]] || die "Referenced GGUF is missing: $resolved"
gguf_magic_ok "$resolved" || die "Referenced file is not a valid GGUF: $resolved"
realpath -e -- "$resolved"
