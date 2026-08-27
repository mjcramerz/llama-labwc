#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

printf '==> Shell syntax checks\n'
for file in scripts/*.sh tests/*.sh; do bash -n "$file"; done
python3 - <<'PYTHON'
from pathlib import Path
path = Path("scripts/hf-resolve.py")
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PYTHON
make --no-print-directory help >/dev/null
make --no-print-directory info >/dev/null
make --no-print-directory models >/dev/null

for test_script in \
    tests/test-manifest.sh \
    tests/test-resolver.sh \
    tests/test-download.sh \
    tests/test-build-wrapper.sh \
    tests/test-profile-builds.sh \
    tests/test-service.sh; do
    printf '==> %s\n' "$test_script"
    "$test_script"
done
printf '==> All tests passed\n'
