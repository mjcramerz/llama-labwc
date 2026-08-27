#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/data"

payload="$tmp/data/model.gguf"
printf 'GGUF' >"$payload"
dd if=/dev/zero bs=1 count=8188 status=none >>"$payload"
size="$(stat -c %s "$payload")"
sha="$(sha256sum "$payload" | awk '{print $1}')"
cat >"$tmp/data/api.json" <<JSON
{"siblings":[{"rfilename":"Qwen3.5-0.8B-Q4_K_M.gguf","size":$size,"lfs":{"sha256":"$sha","size":$size}}]}
JSON

cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
output=''; config=''; url=''
while (($#)); do
    case "$1" in
        --output|--config|--connect-timeout|--retry|--retry-delay|--continue-at)
            key=$1; value=${2-}; shift 2
            [[ "$key" == --output ]] && output=$value
            [[ "$key" == --config ]] && config=$value
            ;;
        --location|--fail|--show-error|--silent|--retry-all-errors) shift ;;
        *) url=$1; shift ;;
    esac
done
printf 'url=%s config=%s hf_env=%s\n' "$url" "$config" "${HF_TOKEN-unset}" >>"$FAKE_CURL_LOG"
if [[ "$url" == *'/api/models/'* ]]; then
    cp "$FAKE_API_JSON" "$output"
else
    cp "$FAKE_PAYLOAD" "$output"
fi
SH
chmod +x "$tmp/bin/curl"

common=(
    CONFIG_FROM_MAKE=1 ROOT_DIR="$ROOT" ALLOW_EXTERNAL_DIRS=1
    SOURCE_DIR="$tmp/source" BUILD_DIR="$tmp/build" OUTPUT_DIR="$tmp/output" MODEL_DIR="$tmp/output/models"
    TOOLCHAIN_PATH_PREFIX="$tmp/bin:/usr/bin:/bin" PATH="$tmp/bin:$PATH"
    FAKE_API_JSON="$tmp/data/api.json" FAKE_PAYLOAD="$payload" FAKE_CURL_LOG="$tmp/curl.log"
)

env "${common[@]}" MODEL=qwen3.5-0.8b-q4_k_m HF_TOKEN=hf_test_secret "$ROOT/scripts/download-model.sh" >/dev/null
model_dir="$tmp/output/models/qwen3.5-0.8b-q4_k_m"
[[ -s "$model_dir/model.path" && -s "$model_dir/files.tsv" && -s "$model_dir/download.meta" ]]
primary="$model_dir/$(cat "$model_dir/model.path")"
cmp -s "$payload" "$primary"
[[ -L "$tmp/output/models/qwen3.5-0.8b-q4_k_m.gguf" ]]
[[ "$(grep -c '^url=' "$tmp/curl.log")" == 2 ]]
! grep -q 'hf_test_secret' "$tmp/curl.log"
grep -q 'hf_env=unset' "$tmp/curl.log"
while read -r cfg; do [[ -z "$cfg" || ! -e "$cfg" ]]; done < <(sed -n 's/.* config=\([^ ]*\).*/\1/p' "$tmp/curl.log")

before="$(wc -l <"$tmp/curl.log")"
env "${common[@]}" MODEL=qwen3.5-0.8b-q4_k_m OFFLINE=1 "$ROOT/scripts/download-model.sh" >/dev/null
after="$(wc -l <"$tmp/curl.log")"
[[ "$before" == "$after" ]]

printf 'BROKEN' >"$primary"
env "${common[@]}" MODEL=qwen3.5-0.8b-q4_k_m "$ROOT/scripts/download-model.sh" >/dev/null
cmp -s "$payload" "$primary"
find "$model_dir" -maxdepth 1 -name '*.corrupt.*' -print -quit | grep -q .

before="$(wc -l <"$tmp/curl.log")"
env "${common[@]}" MODEL=qwen3.5-0.8b-q4_k_m FORCE_DOWNLOAD=1 "$ROOT/scripts/download-model.sh" >/dev/null
after="$(wc -l <"$tmp/curl.log")"
(( after == before + 2 ))

cat >"$tmp/data/api-no-sha.json" <<JSON
{"siblings":[{"rfilename":"Custom-Q4_K_M.gguf","size":$size}]}
JSON
if env "${common[@]}" FAKE_API_JSON="$tmp/data/api-no-sha.json" MODEL=custom-test HF_REPO=example/custom-gguf STRICT_CHECKSUM=1 "$ROOT/scripts/download-model.sh" >/dev/null 2>&1; then
    echo 'STRICT_CHECKSUM accepted a file without published SHA-256' >&2
    exit 1
fi
printf 'download: ok\n'
