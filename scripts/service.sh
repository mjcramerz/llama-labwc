#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_service_config
action=${1:-status}
unit_name="${SERVICE_NAME}.service"
render_dir="$OUTPUT_DIR_ABS/systemd"
render_unit="$render_dir/$unit_name"
render_config="$render_dir/${SERVICE_NAME}.conf"
user_unit_dir="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}/systemd/user"
installed_unit="$user_unit_dir/$unit_name"
managed_marker='# Managed by llama.cpp native-builder'

require_user_systemd() {
    require_cmd systemctl
    systemctl --user show-environment >/dev/null 2>&1 \
        || die "The systemd user manager is unavailable. Log in normally or enable a user manager before using service targets."
}

assert_bind_security() {
    case "$SERVER_HOST" in
        127.0.0.1|localhost|::1|'[::1]') ;;
        *) [[ -n "$SERVER_API_KEY" ]] || die "Non-loopback SERVER_HOST requires SERVER_API_KEY" ;;
    esac
}

shell_assignment() {
    local name=$1 value=${!1-}
    printf '%s=%q\n' "$name" "$value"
}

systemd_escape() {
    local value=$1
    value=${value//%/%%}
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

render_service() {
    assert_bind_security
    [[ -x "$OUTPUT_DIR_ABS/bin/llama-server" ]] || die "Build llama-server before rendering the service"
    if [[ -n "$SERVER_MODEL_PATH" ]]; then
        [[ -f "$SERVER_MODEL_PATH" ]] || die "SERVER_MODEL_PATH does not exist: $SERVER_MODEL_PATH"
        gguf_magic_ok "$SERVER_MODEL_PATH" || die "SERVER_MODEL_PATH is not GGUF"
    else
        MODEL="$SERVER_MODEL" "$SCRIPT_DIR/model-path.sh" --model >/dev/null
    fi

    if [[ -e "$OUTPUT_DIR_ABS" && ! -f "$OUTPUT_DIR_ABS/.native-builder-output" ]]; then
        die "Refusing to write service files into an unmarked OUTPUT_DIR"
    fi
    mkdir -p "$render_dir"
    printf 'native llama.cpp output directory\nroot=%s\n' "$ROOT_DIR" >"$OUTPUT_DIR_ABS/.native-builder-output"

    config_tmp="$render_config.tmp.$$"
    {
        printf '# Managed by llama.cpp native-builder. Contains secrets; mode must remain 0600.\n'
        shell_assignment ROOT_DIR
        shell_assignment SOURCE_DIR
        shell_assignment BUILD_DIR
        shell_assignment OUTPUT_DIR
        shell_assignment MODEL_DIR
        shell_assignment ALLOW_EXTERNAL_DIRS
        shell_assignment SERVER_MODEL
        shell_assignment SERVER_MODEL_PATH
        shell_assignment SERVER_ALIAS
        shell_assignment SERVER_HOST
        shell_assignment SERVER_PORT
        shell_assignment SERVER_THREADS
        shell_assignment SERVER_THREADS_BATCH
        shell_assignment SERVER_CTX_SIZE
        shell_assignment SERVER_PARALLEL
        shell_assignment SERVER_GPU_LAYERS
        shell_assignment SERVER_DEVICE
        shell_assignment SERVER_FLASH_ATTN
        shell_assignment SERVER_LOAD_MODE
        shell_assignment SERVER_KEEP_MODEL_LOADED
        shell_assignment SERVER_SLEEP_IDLE_SECONDS
        shell_assignment SERVER_PIN_MODEL
        shell_assignment SERVER_FULL_GPU_OFFLOAD
        shell_assignment SERVER_CACHE_TYPE_K
        shell_assignment SERVER_CACHE_TYPE_V
        shell_assignment SERVER_CONT_BATCHING
        shell_assignment SERVER_METRICS
        shell_assignment SERVER_EMBEDDINGS
        shell_assignment SERVER_RERANKING
        shell_assignment SERVER_JINJA
        shell_assignment SERVER_API_KEY
        shell_assignment SERVER_TIMEOUT
        shell_assignment SERVER_EXTRA_ARGS
    } >"$config_tmp"
    chmod 0600 "$config_tmp"
    mv -f -- "$config_tmp" "$render_config"

    unit_tmp="$render_unit.tmp.$$"
    root_escaped="$(systemd_escape "$ROOT_DIR")"
    launcher_escaped="$(systemd_escape "$SCRIPT_DIR/server-launch.sh")"
    config_escaped="$(systemd_escape "$render_config")"
    cat >"$unit_tmp" <<UNIT
$managed_marker
[Unit]
Description=Host-native llama.cpp server ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
WorkingDirectory="$root_escaped"
Environment="LLAMA_SERVER_CONFIG=$config_escaped"
ExecStart="$launcher_escaped"
Restart=$SERVICE_RESTART
RestartSec=$SERVICE_RESTART_SEC
TimeoutStopSec=$SERVICE_TIMEOUT_STOP_SEC
KillSignal=SIGINT
LimitMEMLOCK=infinity
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
UMask=0077

[Install]
WantedBy=default.target
UNIT
    chmod 0644 "$unit_tmp"
    mv -f -- "$unit_tmp" "$render_unit"
    info "Rendered unit: $render_unit"
    info "Rendered private configuration: $render_config"
}

assert_managed_installed_unit() {
    [[ -f "$installed_unit" ]] || die "User unit is not installed: $installed_unit"
    grep -Fqx "$managed_marker" "$installed_unit" \
        || die "Refusing to modify an installed unit not managed by this repository: $installed_unit"
}

case "$action" in
    render)
        render_service
        ;;
    enable)
        [[ "$ENABLE_USER_SERVICE" == "1" ]] \
            || die "Explicit opt-in required: make service-enable ENABLE_USER_SERVICE=1"
        require_user_systemd
        render_service
        mkdir -p "$user_unit_dir"
        if [[ -f "$installed_unit" ]]; then
            assert_managed_installed_unit
        fi
        install -m 0644 "$render_unit" "$installed_unit"
        systemctl --user daemon-reload
        if [[ "$SERVICE_AUTOSTART" == "1" ]]; then
            systemctl --user enable "$unit_name"
        else
            systemctl --user disable "$unit_name" >/dev/null 2>&1 || true
        fi
        if [[ "$SERVICE_START_NOW" == "1" ]]; then
            systemctl --user restart "$unit_name"
        fi
        info "Installed rootless unit: $installed_unit"
        if command -v loginctl >/dev/null 2>&1; then
            linger="$(loginctl show-user "${USER:-$(id -un)}" -p Linger --value 2>/dev/null || true)"
            [[ "$linger" != no ]] || warn "User lingering is disabled; the service normally stops after the last login session ends"
        fi
        ;;
    disable)
        require_user_systemd
        assert_managed_installed_unit
        systemctl --user disable --now "$unit_name"
        ;;
    start|stop|restart)
        require_user_systemd
        assert_managed_installed_unit
        systemctl --user "$action" "$unit_name"
        ;;
    status)
        require_user_systemd
        assert_managed_installed_unit
        systemctl --user status "$unit_name" --no-pager
        ;;
    logs)
        require_user_systemd
        assert_managed_installed_unit
        require_cmd journalctl
        exec journalctl --user -u "$unit_name" -f
        ;;
    uninstall)
        require_user_systemd
        if [[ -f "$installed_unit" ]]; then
            assert_managed_installed_unit
            systemctl --user disable --now "$unit_name" >/dev/null 2>&1 || true
            rm -f -- "$installed_unit"
            systemctl --user daemon-reload
            systemctl --user reset-failed "$unit_name" >/dev/null 2>&1 || true
            info "Removed managed user unit: $installed_unit"
        else
            info "No installed user unit to remove"
        fi
        ;;
    *)
        die "Unknown service action '$action' (render, enable, disable, start, stop, restart, status, logs, uninstall)"
        ;;
esac
