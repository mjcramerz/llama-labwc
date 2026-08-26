#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat >"$tmp/repo.json" <<'JSON'
{
  "siblings": [
    {"rfilename":"Model-Q4_K_M.gguf","size":100,"lfs":{"oid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":100}},
    {"rfilename":"split/Model-Q5_K_M-00001-of-00002.gguf","size":60,"lfs":{"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}},
    {"rfilename":"split/Model-Q5_K_M-00002-of-00002.gguf","size":40,"lfs":{"sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}},
    {"rfilename":"vision/mmproj-Model-F16.gguf","size":20,"lfs":{"sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}},
    {"rfilename":"README.md","size":1}
  ]
}
JSON
out="$tmp/out.tsv"
"$ROOT/scripts/hf-resolve.py" --json "$tmp/repo.json" --quant Q4_K_M --include-mmproj >"$out"
grep -q $'^model\tModel-Q4_K_M.gguf\t100\taaaaaaaaaa' "$out"
grep -q $'^mmproj\tvision/mmproj-Model-F16.gguf\t20\tdddddddddd' "$out"
"$ROOT/scripts/hf-resolve.py" --json "$tmp/repo.json" --file Model-Q5_K_M-00001-of-00002.gguf >"$out"
[[ "$(grep -c '^model' "$out")" == 2 ]]
sed '/00002-of-00002/d' "$tmp/repo.json" >"$tmp/incomplete.json"
if "$ROOT/scripts/hf-resolve.py" --json "$tmp/incomplete.json" --quant Q5_K_M >/dev/null 2>&1; then
    echo 'incomplete split unexpectedly resolved' >&2
    exit 1
fi
printf 'resolver: ok\n'
