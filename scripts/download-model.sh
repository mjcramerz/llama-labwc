#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
for command_name in awk basename curl df find grep mktemp od python3 sed sha256sum stat; do
    require_cmd "$command_name"
done
[[ -r "$MANIFEST_PATH" ]] || die "Model manifest not found: $MANIFEST_PATH"
[[ -x "$SCRIPT_DIR/hf-resolve.py" ]] || die "Resolver is not executable: $SCRIPT_DIR/hf-resolve.py"
validate_hf_token

list_models() {
    local index=0 id task family params active quant file_mib min_ram rec_ram vram cores context license repo pattern mmproj notes
    printf '\nCurated llama.cpp GGUF models (resource values are planning estimates)\n\n'
    printf '%-3s %-37s %-13s %-17s %-8s %-7s %-8s %-9s %-7s %-7s %-7s %s\n' \
        '#' 'MODEL ID' 'TASK' 'FAMILY' 'PARAMS' 'ACTIVE' 'WEIGHTS' 'RAM MIN/REC' 'VRAM' 'CPU' 'CTX' 'NOTES'
    printf '%-3s %-37s %-13s %-17s %-8s %-7s %-8s %-9s %-7s %-7s %-7s %s\n' \
        '---' '-------------------------------------' '-------------' '-----------------' '--------' '-------' '--------' '---------' '-------' '-------' '-------' '-----'
    while IFS=$'\t' read -r id task family params active quant file_mib min_ram rec_ram vram cores context license repo pattern mmproj notes; do
        [[ -z "$id" || "$id" == \#* || "$id" == "id" ]] && continue
        ((index += 1))
        printf '%-3d %-37s %-13s %-17s %-8s %-7s %-8s %-9s %-7s %-7s %-7s %s\n' \
            "$index" "$id" "$task" "$family" "$(format_params_b "$params")" \
            "$(format_params_b "$active")" "$(format_mib "$file_mib")/$quant" \
            "${min_ram}/${rec_ram}G" "${vram}G" "$cores" "${context}K" "$notes"
    done <"$MANIFEST_PATH"
    printf '\nLicenses are model-specific. Inspect the selected repository/model card before use or redistribution.\n'
    printf 'Custom GGUF: make download HF_REPO=owner/repo HF_QUANT=Q4_K_M\n'
    printf 'Exact file: make download HF_REPO=owner/repo HF_FILE=path/model.gguf\n\n'
}

lookup_model() {
    local needle=$1 index=0 row_id
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* || "$line" == id$'\t'* ]] && continue
        ((index += 1))
        row_id=${line%%$'\t'*}
        if [[ "$needle" == "$row_id" || "$needle" == "$index" ]]; then
            printf '%s\n' "$line"
            return 0
        fi
    done <"$MANIFEST_PATH"
    return 1
}

prepare_model_root() {
    local marker="$MODEL_DIR_ABS/.native-builder-models"
    local output_marker="$OUTPUT_DIR_ABS/.native-builder-output"
    if [[ -e "$MODEL_DIR_ABS" && ! -d "$MODEL_DIR_ABS" ]]; then
        die "MODEL_DIR exists but is not a directory: $MODEL_DIR_ABS"
    fi
    if [[ -d "$MODEL_DIR_ABS" && ! -f "$marker" ]] \
        && [[ -n "$(find "$MODEL_DIR_ABS" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        die "Refusing to manage an unmarked non-empty MODEL_DIR: $MODEL_DIR_ABS"
    fi
    if [[ "$MODEL_DIR_ABS" == "$OUTPUT_DIR_ABS" || "$MODEL_DIR_ABS" == "$OUTPUT_DIR_ABS/"* ]]; then
        if [[ -e "$OUTPUT_DIR_ABS" && ! -d "$OUTPUT_DIR_ABS" ]]; then
            die "OUTPUT_DIR exists but is not a directory: $OUTPUT_DIR_ABS"
        fi
        if [[ -d "$OUTPUT_DIR_ABS" && ! -f "$output_marker" ]] \
            && [[ -n "$(find "$OUTPUT_DIR_ABS" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            die "Refusing to use an unmarked non-empty OUTPUT_DIR: $OUTPUT_DIR_ABS"
        fi
        mkdir -p "$OUTPUT_DIR_ABS"
        printf 'native llama.cpp output directory\nroot=%s\n' "$ROOT_DIR" >"$output_marker"
    fi
    mkdir -p "$MODEL_DIR_ABS/.locks"
    printf 'native llama.cpp model directory\nroot=%s\n' "$ROOT_DIR" >"$marker"
}

validate_payload() {
    local file=$1 expected_size=${2:-0} expected_sha=${3:--} label=${4:-GGUF}
    [[ -f "$file" ]] || { warn "$label is missing: $file"; return 1; }
    local size actual
    size="$(stat -c %s "$file" 2>/dev/null || printf 0)"
    [[ "$size" =~ ^[0-9]+$ ]] && (( size >= 8 )) || { warn "$label is implausibly small: $file"; return 1; }
    if head -c 512 "$file" 2>/dev/null | grep -aEiq '<!doctype|<html|access denied|not found|unauthorized|forbidden|oid sha256:'; then
        warn "$label looks like an error page or Git LFS pointer: $file"
        return 1
    fi
    gguf_magic_ok "$file" || { warn "$label does not have GGUF magic bytes: $file"; return 1; }
    if [[ "$expected_size" =~ ^[0-9]+$ ]] && (( expected_size > 0 && size != expected_size )); then
        warn "$label size mismatch for $file: expected $expected_size bytes, got $size"
        return 1
    fi
    if [[ "$expected_sha" != "-" && -n "$expected_sha" ]]; then
        if [[ "$VERIFY_REMOTE_SHA256" == "1" || "$STRICT_CHECKSUM" == "1" ]]; then
            actual="$(sha256sum "$file" | awk '{print $1}')"
            [[ "$actual" == "$expected_sha" ]] || { warn "$label SHA-256 mismatch for $file"; return 1; }
        fi
    elif [[ "$STRICT_CHECKSUM" == "1" ]]; then
        warn "$label has no published LFS SHA-256 while STRICT_CHECKSUM=1: $file"
        return 1
    fi
}

validate_existing_model() {
    local directory=$1 primary rel role size sha
    [[ -f "$directory/.native-builder-model" && -s "$directory/model.path" && -s "$directory/files.tsv" ]] || return 1
    primary="$(head -n1 "$directory/model.path")"
    [[ "$primary" != /* && "$primary" != *..* && -f "$directory/$primary" ]] || return 1
    while IFS=$'\t' read -r role rel size sha; do
        [[ -n "$role" && -n "$rel" && "$rel" != /* && "$rel" != *..* ]] || return 1
        validate_payload "$directory/$rel" "$size" "$sha" "$role" >/dev/null 2>&1 || return 1
    done <"$directory/files.tsv"
}

make_auth_config() {
    [[ -n "$HF_TOKEN" ]] || return 0
    auth_config="$(mktemp)"
    chmod 0600 "$auth_config"
    printf 'header = "Authorization: Bearer %s"\n' "$HF_TOKEN" >"$auth_config"
}

curl_fetch() {
    local url=$1 output=$2 resume=${3:-0}
    local -a args=(
        --location --fail --show-error --silent
        --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT"
        --retry "$DOWNLOAD_RETRIES" --retry-delay 2 --retry-all-errors
        --output "$output"
    )
    [[ "$resume" == "1" ]] && args+=(--continue-at -)
    [[ -z "$auth_config" ]] || args+=(--config "$auth_config")
    env -u HF_TOKEN curl "${args[@]}" "$url"
}

corrupt_name() {
    printf '%s.corrupt.%s.%s\n' "$1" "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

if [[ "${1:-}" == "--list" ]]; then
    list_models
    exit 0
fi

selection="${MODEL:-${1:-}}"
if [[ -z "$selection" && -z "$HF_REPO" ]]; then
    if ! exec 3<>/dev/tty; then
        die "No interactive terminal. Supply MODEL=<catalog-id> or HF_REPO=owner/repo"
    fi
    list_models >&3
    printf 'Select by number/name, or c for a custom Hugging Face GGUF repo [qwen3.5-0.8b-q4_k_m]: ' >&3
    IFS= read -r selection <&3 || true
    selection="${selection:-qwen3.5-0.8b-q4_k_m}"
    if [[ "$selection" == "c" || "$selection" == "custom" ]]; then
        printf 'Hugging Face repository (owner/repo): ' >&3
        IFS= read -r HF_REPO <&3 || true
        printf 'Quant token [Q4_K_M], or leave blank when giving HF_FILE: ' >&3
        IFS= read -r custom_quant <&3 || true
        HF_QUANT="${custom_quant:-Q4_K_M}"
    elif [[ "$selection" == "q" || "$selection" == "quit" ]]; then
        exec 3>&-
        info "Download cancelled"
        exit 0
    fi
    exec 3>&-
fi

catalog_row=''
model_id=''
task='Custom'
family='Custom GGUF'
params='-'
active='-'
quant="$HF_QUANT"
estimated_mib=0
min_ram=0
rec_ram=0
full_vram=0
cores='-'
context='-'
license='See model card'
repo="$HF_REPO"
pattern=''
mmproj_pattern=''
notes='User-selected Hugging Face GGUF repository.'

if [[ -n "$selection" ]]; then
    catalog_row="$(lookup_model "$selection" || true)"
fi
if [[ -n "$catalog_row" ]]; then
    IFS=$'\t' read -r model_id task family params active quant estimated_mib min_ram rec_ram full_vram cores context license repo pattern mmproj_pattern notes <<<"$catalog_row"
    [[ -z "$HF_REPO" ]] || repo="$HF_REPO"
else
    [[ -n "$repo" ]] || { list_models >&2; die "Unknown model '$selection'. Use a catalog ID or HF_REPO=owner/repo"; }
    if [[ -n "$selection" ]]; then
        model_id="$selection"
        model_id_valid "$model_id" || die "MODEL must be a safe local ID when HF_REPO is supplied"
    else
        suffix="${HF_FILE:-$HF_QUANT}"
        model_id="$(slugify "${repo##*/}-$suffix")"
    fi
fi

[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "HF_REPO must have the form owner/repository"
model_id_valid "$model_id" || die "Unsafe model ID: $model_id"
[[ "$HF_REVISION" != *$'\n'* && "$HF_REVISION" != *$'\r'* && -n "$HF_REVISION" ]] || die "HF_REVISION is invalid"
prepare_model_root

target_dir="$MODEL_DIR_ABS/$model_id"
if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
    die "Model destination exists but is not a directory: $target_dir"
fi
if [[ -d "$target_dir" && -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" \
      && ! -f "$target_dir/.native-builder-model" ]]; then
    die "Refusing to manage unmarked model directory: $target_dir"
fi
mkdir -p "$target_dir"
printf 'native llama.cpp model\nid=%s\nroot=%s\n' "$model_id" "$ROOT_DIR" >"$target_dir/.native-builder-model"

lock_dir="$MODEL_DIR_ABS/.locks/$model_id.lock"
auth_config=''
api_json=''
resolved_tsv=''
cleanup() {
    [[ -z "$auth_config" ]] || rm -f -- "$auth_config"
    [[ -z "$api_json" ]] || rm -f -- "$api_json"
    [[ -z "$resolved_tsv" ]] || rm -f -- "$resolved_tsv"
    rmdir -- "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
mkdir "$lock_dir" 2>/dev/null || die "Another process is downloading model '$model_id'"

log "Selected $model_id"
info "Task: $task | Family: $family | Parameters: $(format_params_b "$params") total, $(format_params_b "$active") active"
info "Quant: $quant | Estimated weights: $(format_mib "$estimated_mib") | RAM: ${min_ram}-${rec_ram} GiB | full-offload VRAM: ${full_vram} GiB"
info "License: $license | Repository: $repo@$HF_REVISION"
info "$notes"

if validate_existing_model "$target_dir" && [[ "$FORCE_DOWNLOAD" == "0" ]]; then
    info "Model already exists and passed validation: $target_dir"
    cat "$target_dir/model.path" | sed "s#^#$target_dir/#"
    exit 0
fi
if [[ "$OFFLINE" == "1" ]]; then
    die "OFFLINE=1 and no complete, valid local copy of '$model_id' is available"
fi

host_ram="$(total_ram_gib)"
if [[ "$min_ram" =~ ^[0-9]+$ ]] && (( min_ram > 0 && host_ram > 0 && host_ram < min_ram )); then
    message="Host has about ${host_ram} GiB total RAM; catalog estimates at least ${min_ram} GiB for this model"
    [[ "$STRICT_RESOURCES" == "1" ]] && die "$message" || warn "$message"
elif [[ "$rec_ram" =~ ^[0-9]+$ ]] && (( rec_ram > 0 && host_ram > 0 && host_ram < rec_ram )); then
    warn "Host has about ${host_ram} GiB total RAM; ${rec_ram} GiB is recommended for comfortable use"
fi

make_auth_config
# Keep the token only in the mode-0600 curl configuration from this point on.
unset HF_TOKEN
api_json="$(mktemp)"
resolved_tsv="$(mktemp)"
repo_path="$(urlencode_path "$repo")"
revision_component="$(urlencode_component "$HF_REVISION")"
api_url="${HF_API_BASE%/}/${repo_path}/revision/${revision_component}?blobs=true"
log "Resolving GGUF files from Hugging Face"
if ! curl_fetch "$api_url" "$api_json" 0; then
    die "Could not query Hugging Face model metadata: $repo@$HF_REVISION"
fi

resolver_args=(--json "$api_json")
[[ -n "$HF_FILE" ]] && resolver_args+=(--file "$HF_FILE")
[[ -z "$HF_FILE" && -n "$pattern" && "$pattern" != "-" ]] && resolver_args+=(--pattern "$pattern")
[[ -z "$HF_FILE" && -n "$quant" ]] && resolver_args+=(--quant "$quant")
if [[ "$DOWNLOAD_MMPROJ" == "1" ]]; then
    resolver_args+=(--include-mmproj)
    [[ -n "$mmproj_pattern" && "$mmproj_pattern" != "-" ]] && resolver_args+=(--mmproj-pattern "$mmproj_pattern")
fi
"$SCRIPT_DIR/hf-resolve.py" "${resolver_args[@]}" >"$resolved_tsv"
[[ -s "$resolved_tsv" ]] || die "Resolver returned no GGUF files"

# Reject duplicate basenames because local model directories are intentionally flat.
duplicate="$(awk -F '\t' '{n=$2; sub(/^.*\//,"",n); if (++seen[n] == 2) print n}' "$resolved_tsv" | head -n1)"
[[ -z "$duplicate" ]] || die "Repository selection contains duplicate basename '$duplicate'"

expected_total="$(awk -F '\t' '{s += $3} END {printf "%.0f\n", s}' "$resolved_tsv")"
available_kib="$(df -Pk "$MODEL_DIR_ABS" | awk 'NR==2 {print $4}')"
if [[ "$expected_total" =~ ^[0-9]+$ ]] && (( expected_total > 0 )); then
    required_kib=$((expected_total / 1024 + expected_total / 10240 + 65536))
    if [[ "$available_kib" =~ ^[0-9]+$ ]] && (( available_kib < required_kib )); then
        die "Insufficient free disk space; resolved files need about $((expected_total / 1024 / 1024)) MiB plus download overhead"
    fi
fi

# Download and validate every replacement before exposing new files.
declare -a roles=() remote_paths=() local_names=() expected_sizes=() remote_shas=() candidates=()
while IFS=$'\t' read -r role remote size sha; do
    [[ "$role" == "model" || "$role" == "mmproj" ]] || die "Resolver returned unsupported role: $role"
    local_name="$(basename -- "$remote")"
    target="$target_dir/$local_name"
    part="$target.part"
    if [[ "$FORCE_DOWNLOAD" == "1" ]]; then
        rm -f -- "$part"
    fi
    if [[ "$FORCE_DOWNLOAD" == "0" && -f "$target" ]] \
        && validate_payload "$target" "$size" "$sha" "$role"; then
        candidate="$target"
        info "Reusing verified file: $local_name"
    else
        if [[ "$FORCE_DOWNLOAD" == "0" && -f "$target" ]]; then
            bad="$(corrupt_name "$target")"
            mv -f -- "$target" "$bad"
            warn "Preserved invalid completed file as $bad"
        fi
        encoded_remote="$(urlencode_path "$remote")"
        encoded_revision="$(urlencode_component "$HF_REVISION")"
        url="${HF_DOWNLOAD_BASE%/}/${repo_path}/resolve/${encoded_revision}/${encoded_remote}?download=true"
        log "Downloading $remote"
        if ! curl_fetch "$url" "$part" 1; then
            die "Download failed; resumable partial data remains at $part"
        fi
        if ! validate_payload "$part" "$size" "$sha" "$role"; then
            bad="$(corrupt_name "$target")"
            mv -f -- "$part" "$bad" 2>/dev/null || true
            die "Validation failed; bad payload retained as $bad"
        fi
        candidate="$part"
    fi
    roles+=("$role")
    remote_paths+=("$remote")
    local_names+=("$local_name")
    expected_sizes+=("$size")
    remote_shas+=("$sha")
    candidates+=("$candidate")
done <"$resolved_tsv"

model_count=0
mmproj_count=0
primary_name=''
for i in "${!candidates[@]}"; do
    target="$target_dir/${local_names[$i]}"
    if [[ "${candidates[$i]}" != "$target" ]]; then
        [[ ! -f "$target" ]] || mv -f -- "$target" "$(corrupt_name "$target")"
        mv -f -- "${candidates[$i]}" "$target"
    fi
    chmod 0644 "$target"
    if [[ "${roles[$i]}" == "model" ]]; then
        ((model_count += 1))
        [[ -n "$primary_name" ]] || primary_name="${local_names[$i]}"
    else
        ((mmproj_count += 1))
    fi
done
(( model_count > 0 )) || die "No model GGUF was installed"

files_tmp="$target_dir/files.tsv.tmp.$$"
meta_tmp="$target_dir/download.meta.tmp.$$"
path_tmp="$target_dir/model.path.tmp.$$"
mmproj_tmp="$target_dir/mmproj.path.tmp.$$"
: >"$files_tmp"
: >"$mmproj_tmp"
{
    printf 'model_id=%s\n' "$model_id"
    printf 'repository=%s\n' "$repo"
    printf 'revision=%s\n' "$HF_REVISION"
    printf 'downloaded_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'catalog_task=%s\n' "$task"
    printf 'catalog_family=%s\n' "$family"
    printf 'catalog_quant=%s\n' "$quant"
    printf 'catalog_license=%s\n' "$license"
} >"$meta_tmp"
for i in "${!local_names[@]}"; do
    target="$target_dir/${local_names[$i]}"
    local_sha="$(sha256sum "$target" | awk '{print $1}')"
    actual_size="$(stat -c %s "$target")"
    printf '%s\t%s\t%s\t%s\n' "${roles[$i]}" "${local_names[$i]}" "$actual_size" "$local_sha" >>"$files_tmp"
    printf 'file=%s|%s|%s|%s|%s\n' "${roles[$i]}" "${remote_paths[$i]}" "$actual_size" "${remote_shas[$i]}" "$local_sha" >>"$meta_tmp"
    [[ "${roles[$i]}" != "mmproj" ]] || printf '%s\n' "${local_names[$i]}" >>"$mmproj_tmp"
done
printf '%s\n' "$primary_name" >"$path_tmp"
mv -f -- "$files_tmp" "$target_dir/files.tsv"
mv -f -- "$meta_tmp" "$target_dir/download.meta"
mv -f -- "$path_tmp" "$target_dir/model.path"
if (( mmproj_count > 0 )); then
    mv -f -- "$mmproj_tmp" "$target_dir/mmproj.path"
else
    rm -f -- "$mmproj_tmp" "$target_dir/mmproj.path"
    [[ "$DOWNLOAD_MMPROJ" == "0" ]] || warn "No matching multimodal projection GGUF was found"
fi
chmod 0644 "$target_dir/files.tsv" "$target_dir/download.meta" "$target_dir/model.path"
[[ ! -f "$target_dir/mmproj.path" ]] || chmod 0644 "$target_dir/mmproj.path"

# A convenience link is safe only for one model shard; split models are resolved
# through model.path so llama.cpp can discover the remaining shards.
link="$MODEL_DIR_ABS/$model_id.gguf"
if (( model_count == 1 )); then
    ln -sfn "$model_id/$primary_name" "$link"
else
    rm -f -- "$link"
fi

if (( mmproj_count > 0 )); then
    info "Downloaded and verified $model_count model GGUF file(s) and $mmproj_count projection file(s)"
else
    info "Downloaded and verified $model_count model GGUF file(s)"
fi
info "Model directory: $target_dir"
printf '%s\n' "$target_dir/$primary_name"
