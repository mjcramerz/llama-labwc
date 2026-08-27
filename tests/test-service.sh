#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/output/bin" "$tmp/output/models/demo" "$tmp/fake-bin" "$tmp/home"
printf 'native llama.cpp output directory\n' >"$tmp/output/.native-builder-output"
printf 'native llama.cpp model directory\n' >"$tmp/output/models/.native-builder-models"
printf 'native llama.cpp model\n' >"$tmp/output/models/demo/.native-builder-model"
printf 'GGUFdemo' >"$tmp/output/models/demo/demo.gguf"
printf 'demo.gguf\n' >"$tmp/output/models/demo/model.path"
printf 'model\tdemo.gguf\t8\t%s\n' "$(sha256sum "$tmp/output/models/demo/demo.gguf" | awk '{print $1}')" >"$tmp/output/models/demo/files.tsv"
cat >"$tmp/output/bin/llama-server" <<'SH'
#!/usr/bin/env bash
printf 'api=%s\n' "${LLAMA_API_KEY-unset}" >"$FAKE_SERVER_LOG"
printf '%s\n' "$@" >>"$FAKE_SERVER_LOG"
SH
chmod +x "$tmp/output/bin/llama-server"
cat >"$tmp/fake-bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
exit 0
SH
cat >"$tmp/fake-bin/loginctl" <<'SH'
#!/usr/bin/env bash
printf 'no\n'
SH
chmod +x "$tmp/fake-bin/systemctl" "$tmp/fake-bin/loginctl"

common=(
  CONFIG_FROM_MAKE=1 ROOT_DIR="$ROOT" ALLOW_EXTERNAL_DIRS=1
  SOURCE_DIR="$tmp/source" BUILD_DIR="$tmp/build" OUTPUT_DIR="$tmp/output" MODEL_DIR="$tmp/output/models"
  SERVER_MODEL=demo SERVER_API_KEY=top_secret SERVER_PIN_MODEL=1 SERVER_FULL_GPU_OFFLOAD=1
  SERVER_KEEP_MODEL_LOADED=1 SERVER_HOST=127.0.0.1 SERVER_PORT=18080
  SERVICE_NAME=llama-test TOOLCHAIN_PATH_PREFIX="$tmp/fake-bin:/usr/bin:/bin"
  PATH="$tmp/fake-bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/config"
  FAKE_SERVER_LOG="$tmp/server.log" FAKE_SYSTEMCTL_LOG="$tmp/systemctl.log"
)
env "${common[@]}" "$ROOT/scripts/service.sh" render
unit="$tmp/output/systemd/llama-test.service"
config="$tmp/output/systemd/llama-test.conf"
[[ -s "$unit" && -s "$config" ]]
[[ "$(stat -c %a "$config")" == 600 ]]
! grep -q top_secret "$unit"
grep -q top_secret "$config"

cp "$config" "$tmp/insecure.conf"
chmod 0644 "$tmp/insecure.conf"
if env "${common[@]}" LLAMA_SERVER_CONFIG="$tmp/insecure.conf" "$ROOT/scripts/server-launch.sh" >/dev/null 2>&1; then
    echo 'insecure server configuration permissions were accepted' >&2
    exit 1
fi

env "${common[@]}" LLAMA_SERVER_CONFIG="$config" "$ROOT/scripts/server-launch.sh"
grep -q '^api=top_secret$' "$tmp/server.log"
grep -qx -- '--sleep-idle-seconds' "$tmp/server.log"
grep -qx -- '-1' "$tmp/server.log"
grep -qx -- 'mmap+mlock' "$tmp/server.log"
grep -qx -- 'all' "$tmp/server.log"

env "${common[@]}" ENABLE_USER_SERVICE=1 "$ROOT/scripts/service.sh" enable
installed="$tmp/home/config/systemd/user/llama-test.service"
[[ -s "$installed" ]]
if env "${common[@]}" "$ROOT/scripts/clean.sh" build >/dev/null 2>&1; then
    echo 'clean unexpectedly removed files referenced by installed service' >&2
    exit 1
fi
env "${common[@]}" "$ROOT/scripts/service.sh" uninstall
[[ ! -e "$installed" ]]
env "${common[@]}" "$ROOT/scripts/clean.sh" build
[[ ! -e "$tmp/output/bin" && -f "$tmp/output/models/demo/demo.gguf" ]]

if env "${common[@]}" SERVER_HOST=0.0.0.0 SERVER_API_KEY= "$ROOT/scripts/service.sh" render >/dev/null 2>&1; then
    echo 'unauthenticated non-loopback service was accepted' >&2
    exit 1
fi
printf 'service: ok\n'
