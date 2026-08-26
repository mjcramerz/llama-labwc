#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
remote="$tmp/upstream"
mkdir -p "$remote"
cat >"$remote/main.cpp" <<'CPP'
#include <array>
#include <iostream>
#ifndef TARGET_NAME
#define TARGET_NAME "unknown"
#endif
static const std::array<unsigned char, 8192> padding = {1};
int main(int argc, char **argv) {
    if (argc > 1 && std::string(argv[1]) == "--version") {
        std::cout << TARGET_NAME << " fake-version " << int(padding[0]) << "\n";
    }
    return 0;
}
CPP
cat >"$remote/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.14)
project(fake_llama LANGUAGES C CXX)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
foreach(name llama-cli llama-server llama-bench llama-quantize llama-gguf-split)
  add_executable(${name} main.cpp)
  target_compile_features(${name} PRIVATE cxx_std_17)
  target_compile_definitions(${name} PRIVATE TARGET_NAME="${name}")
endforeach()
CMAKE
printf 'fake upstream license\n' >"$remote/LICENSE"
git -C "$remote" init -q
git -C "$remote" config user.email test@example.invalid
git -C "$remote" config user.name test
git -C "$remote" add .
git -C "$remote" commit -qm initial
commit="$(git -C "$remote" rev-parse HEAD)"

common=(
  CONFIG_FROM_MAKE=1 ROOT_DIR="$ROOT" ALLOW_EXTERNAL_DIRS=1
  LLAMA_CPP_REPO="$remote" LLAMA_CPP_REF="$commit"
  SOURCE_DIR="$tmp/source" BUILD_DIR="$tmp/build" OUTPUT_DIR="$tmp/output" MODEL_DIR="$tmp/output/models"
  CMAKE_GENERATOR="Unix Makefiles" BUILD_JOBS=2 STRIP_BINARIES=0 ENABLE_LTO=0 ENABLE_CCACHE=0 ENABLE_OPENMP=0
)
env "${common[@]}" "$ROOT/scripts/source.sh"
env "${common[@]}" "$ROOT/scripts/configure.sh" >/dev/null
env "${common[@]}" "$ROOT/scripts/build.sh" >/dev/null
env "${common[@]}" "$ROOT/scripts/verify.sh"
env "${common[@]}" "$ROOT/scripts/list-devices.sh"
for target in llama-cli llama-server llama-bench llama-quantize llama-gguf-split; do
    [[ -x "$tmp/output/bin/$target" && -L "$tmp/output/$target" ]]
done
grep -q "source_commit=$commit" "$tmp/output/metadata/build-info.txt"
grep -q -- '-O3 -DNDEBUG' "$tmp/output/metadata/build-info.txt"

mkdir -p "$tmp/output/models/sample"
printf 'native llama.cpp model directory\n' >"$tmp/output/models/.native-builder-models"
printf 'native llama.cpp model\n' >"$tmp/output/models/sample/.native-builder-model"
printf 'GGUFfake' >"$tmp/output/models/sample/model.gguf"
printf 'model.gguf\n' >"$tmp/output/models/sample/model.path"
printf 'model\tmodel.gguf\t8\t%s\n' "$(sha256sum "$tmp/output/models/sample/model.gguf" | awk '{print $1}')" >"$tmp/output/models/sample/files.tsv"

env "${common[@]}" "$ROOT/scripts/clean.sh" build
[[ ! -e "$tmp/build" && ! -e "$tmp/output/bin" && -f "$tmp/output/models/sample/model.gguf" && -d "$tmp/source/.git" ]]
env "${common[@]}" "$ROOT/scripts/clean.sh" distclean
[[ ! -e "$tmp/source" && -f "$tmp/output/models/sample/model.gguf" ]]
env "${common[@]}" CONFIRM=YES "$ROOT/scripts/clean.sh" purge
[[ ! -e "$tmp/output" ]]
printf 'build-wrapper: ok\n'
