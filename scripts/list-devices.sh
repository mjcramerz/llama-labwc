#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_common_config
binary="$OUTPUT_DIR_ABS/bin/llama-cli"
[[ -x "$binary" ]] || die "No staged llama-cli at $binary; run make build"
exec "$binary" --list-devices
