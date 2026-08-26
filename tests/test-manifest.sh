#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="$ROOT/models/models.tsv"
[[ -s "$manifest" ]]

awk -F '\t' '
BEGIN { count=0; failed=0 }
/^#/ || $1 == "id" || NF == 0 { next }
{
    count++
    if (NF != 17) { printf "line %d: expected 17 fields, got %d\n", NR, NF > "/dev/stderr"; failed=1 }
    if ($1 !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/) { printf "line %d: unsafe id\n", NR > "/dev/stderr"; failed=1 }
    if (seen[$1]++) { printf "line %d: duplicate id %s\n", NR, $1 > "/dev/stderr"; failed=1 }
    if ($4 !~ /^[0-9]+([.][0-9]+)?$/ || $5 !~ /^[0-9]+([.][0-9]+)?$/) { printf "line %d: invalid parameter count\n", NR > "/dev/stderr"; failed=1 }
    if (($6 == "") || $7 !~ /^[0-9]+$/ || $8 !~ /^[0-9]+$/ || $9 !~ /^[0-9]+$/ || $10 !~ /^[0-9]+$/) { printf "line %d: invalid resource field\n", NR > "/dev/stderr"; failed=1 }
    if ($14 !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/) { printf "line %d: invalid HF repo %s\n", NR, $14 > "/dev/stderr"; failed=1 }
    if (tolower($0) ~ /whisper|tiny[.]en|large-v3-turbo/) { printf "line %d: Whisper model leaked into llama.cpp catalog\n", NR > "/dev/stderr"; failed=1 }
}
END {
    if (count < 30) { printf "expected at least 30 curated models, got %d\n", count > "/dev/stderr"; failed=1 }
    exit failed
}
' "$manifest"

for id in qwen3.5-0.8b-q4_k_m qwen3-8b-q4_k_m llama3.2-3b-instruct-q4_k_m phi4-mini-instruct-q4_k_m qwen3-embedding-0.6b-q8_0; do
    grep -q "^${id}"$'\t' "$manifest"
done
printf 'manifest: ok\n'
