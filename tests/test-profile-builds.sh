#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

for expected in \
    'LLAMA_RAM_BUILD_DIR=.build/ram' \
    'LLAMA_RAM_OUTPUT_DIR=output/ram' \
    'LLAMA_RAM_ARCHIVE_PATH=output/llama-ram.tar.gz' \
    'LLAMA_RAM_ENABLE_SERVER_UI=0' \
    'LLAMA_RAM_USE_PREBUILT_UI=1' \
    'LLAMA_RAM_SERVER_UI_VERSION=b10270' \
    'LLAMA_RAM_SERVER_UI_SHA256=c63b205dc7b5574a3d8f2d7793d1d1bbad886a81a14a04c591d536b05ac4d8ba' \
    'LLAMA_CUDA_BUILD_DIR=.build/cuda' \
    'LLAMA_CUDA_OUTPUT_DIR=output/cuda' \
    'LLAMA_CUDA_ARCHIVE_PATH=output/llama-cuda.tar.gz' \
    'LLAMA_CUDA_CUDA_ARCHS=61' \
    'LLAMA_CUDA_CUDA_NO_PEER_COPY=1' \
    'LLAMA_CUDA_ENABLE_CUDA_GRAPHS=0' \
    'LLAMA_CUDA_ENABLE_CUDA_NCCL=0' \
    'LLAMA_CUDA_ENABLE_SERVER_UI=0' \
    'LLAMA_CUDA_USE_PREBUILT_UI=1' \
    'LLAMA_CUDA_SERVER_UI_VERSION=b10270' \
    'LLAMA_CUDA_SERVER_UI_SHA256=c63b205dc7b5574a3d8f2d7793d1d1bbad886a81a14a04c591d536b05ac4d8ba' \
    'LLAMA_CUDA_CMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc'; do
    grep -Fqx -- "$expected" "$ROOT_DIR/.env.example"
done

fake_upstream="$tmp/fake-upstream"
fake_bin="$tmp/bin"
mkdir -p -- "$fake_upstream" "$fake_bin"
cat >"$fake_upstream/main.cpp" <<'CPP'
#include <array>
#include <iostream>
#include <string>
#ifndef TARGET_NAME
#define TARGET_NAME "unknown"
#endif
static const std::array<unsigned char, 8192> padding = {1};
int main(int argc, char **argv) {
    if (argc > 1 && std::string(argv[1]) == "--version") {
        std::cout << TARGET_NAME << " fake-profile " << int(padding[0]) << "\n";
    }
    return 0;
}
CPP
cat >"$fake_upstream/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.18)
project(fake_llama_profiles LANGUAGES C CXX)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
if(LLAMA_USE_PREBUILT_UI)
  if(NOT DEFINED ENV{HF_UI_VERSION})
    message(FATAL_ERROR "HF_UI_VERSION was not provided")
  endif()
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/tools/ui/dist")
  file(WRITE "${CMAKE_BINARY_DIR}/tools/ui/dist/index.html" "<html>fake UI</html>\n")
  file(WRITE "${CMAKE_BINARY_DIR}/tools/ui/dist.tar.gz" "fake prebuilt UI archive\n")
  file(SHA256 "${CMAKE_BINARY_DIR}/tools/ui/dist.tar.gz" FAKE_UI_SHA256)
  file(WRITE "${CMAKE_BINARY_DIR}/tools/ui/dist.tar.gz.sha256" "${FAKE_UI_SHA256}  dist.tar.gz\n")
  file(WRITE "${CMAKE_BINARY_DIR}/tools/ui/.ui-stamp" "$ENV{HF_UI_VERSION}")
endif()
foreach(name llama-cli llama-server llama-bench llama-quantize llama-gguf-split)
  add_executable(${name} main.cpp)
  target_compile_features(${name} PRIVATE cxx_std_17)
  target_compile_definitions(${name} PRIVATE TARGET_NAME="${name}")
endforeach()
CMAKE
printf 'fake upstream license\n' >"$fake_upstream/LICENSE"
git -C "$fake_upstream" init -q
git -C "$fake_upstream" config user.email test@example.invalid
git -C "$fake_upstream" config user.name test
git -C "$fake_upstream" add .
git -C "$fake_upstream" commit -qm initial
ref="$(git -C "$fake_upstream" rev-parse HEAD)"
fake_ui_version=fake-ui-v1
fake_ui_sha256="$(printf 'fake prebuilt UI archive\n' | sha256sum | awk '{print $1}')"

cat >"$fake_bin/nvcc" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
for argument in "$@"; do
    if [[ "$argument" == "--version" ]]; then
        printf 'Cuda compilation tools, release 12.8, V12.8.0\n'
        exit 0
    fi
done
output=''
while (($#)); do
    case "$1" in
        -o)
            output=$2
            shift 2
            ;;
        *) shift ;;
    esac
done
[[ -n "$output" ]] || exit 2
: >"$output"
SH
chmod 0755 "$fake_bin/nvcc"

common_make_args=(
    --no-print-directory
    "LLAMA_CPP_REPO=$fake_upstream"
    "LLAMA_CPP_REF=$ref"
    ALLOW_EXTERNAL_DIRS=1
    OFFLINE=0
    SOURCE_UPDATE=0
    FORCE_SOURCE_RESET=0
)

run_make() {
    local log_file=$1
    shift
    if ! PATH="$fake_bin:$PATH" make -C "$ROOT_DIR" "$@" >"$log_file" 2>&1; then
        cat "$log_file" >&2
        return 1
    fi
}

assert_staged_ui_bundle() {
    local build_dir=$1 output_dir=$2 expected_version=$3 expected_sha256=$4
    local ui_dir="$output_dir/share/llama-ui"
    cmp -s "$build_dir/tools/ui/dist.tar.gz" "$ui_dir/dist.tar.gz"
    [[ "$(sha256sum "$ui_dir/dist.tar.gz" | awk '{print $1}')" == "$expected_sha256" ]]
    (
        cd -- "$ui_dir"
        sha256sum --check --strict SHA256SUMS >/dev/null
    )
    grep -Fqx 'format=llama-ui-prebuilt-v1' "$ui_dir/bundle-info.txt"
    grep -Fqx 'bucket=ggml-org/llama-ui' "$ui_dir/bundle-info.txt"
    grep -Fqx "version=$expected_version" "$ui_dir/bundle-info.txt"
    grep -Fqx "sha256=$expected_sha256" "$ui_dir/bundle-info.txt"
    grep -Fqx 'embedded_in=llama-server' "$ui_dir/bundle-info.txt"
    grep -Fq 'share/llama-ui/dist.tar.gz' "$output_dir/metadata/SHA256SUMS"
    grep -Fq 'share/llama-ui/SHA256SUMS' "$output_dir/metadata/SHA256SUMS"
    grep -Fq 'share/llama-ui/bundle-info.txt' "$output_dir/metadata/SHA256SUMS"
}

ram_archive="$tmp/artifacts/llama-ram.tar.gz"
ram_args=(
    "${common_make_args[@]}"
    build-ram
    "LLAMA_RAM_SOURCE_DIR=$tmp/source"
    "LLAMA_RAM_BUILD_DIR=$tmp/build/ram"
    "LLAMA_RAM_OUTPUT_DIR=$tmp/output/ram"
    "LLAMA_RAM_MODEL_DIR=$tmp/models"
    "LLAMA_RAM_ARCHIVE_PATH=$ram_archive"
    LLAMA_RAM_SCCACHE_DIR=
    LLAMA_RAM_SCCACHE_SERVER_UDS=
    LLAMA_RAM_CMAKE_GENERATOR=Unix\ Makefiles
    LLAMA_RAM_BUILD_JOBS=2
    LLAMA_RAM_CMAKE_C_COMPILER_LAUNCHER=
    LLAMA_RAM_CMAKE_CXX_COMPILER_LAUNCHER=
    LLAMA_RAM_CMAKE_CUDA_COMPILER_LAUNCHER=
    LLAMA_RAM_GGML_NATIVE=0
    LLAMA_RAM_ENABLE_LTO=0
    LLAMA_RAM_ENABLE_OPENMP=0
    LLAMA_RAM_STRIP_BINARIES=0
    LLAMA_RAM_ENABLE_SERVER_UI=0
    LLAMA_RAM_USE_PREBUILT_UI=1
    LLAMA_RAM_SERVER_UI_HF_BUCKET=ggml-org/llama-ui
    "LLAMA_RAM_SERVER_UI_VERSION=$fake_ui_version"
    "LLAMA_RAM_SERVER_UI_SHA256=$fake_ui_sha256"
    LLAMA_RAM_ENABLE_SERVER_UI_GZIP=1
)
run_make "$tmp/build-ram.log" "${ram_args[@]}"

for target in llama-cli llama-server llama-bench llama-quantize llama-gguf-split; do
    [[ -x "$tmp/output/ram/bin/$target" ]]
done
[[ -f "$ram_archive" ]]
grep -Fqx 'build_profile=ram' "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx 'backend=CPU' "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx 'server_ui=1' "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx 'server_ui_build_from_source=0' "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx 'server_ui_prebuilt=1' "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx "server_ui_asset_version=$fake_ui_version" "$tmp/output/ram/metadata/build-info.txt"
grep -Fqx "server_ui_asset_sha256=$fake_ui_sha256" "$tmp/output/ram/metadata/build-info.txt"
grep -F -- '-DGGML_CUDA=OFF' "$tmp/output/ram/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_BUILD_UI=OFF' "$tmp/output/ram/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_USE_PREBUILT_UI=ON' "$tmp/output/ram/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_UI_HF_BUCKET=ggml-org/llama-ui' "$tmp/output/ram/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_UI_GZIP=ON' "$tmp/output/ram/metadata/cmake-command.txt" >/dev/null
assert_staged_ui_bundle "$tmp/build/ram" "$tmp/output/ram" "$fake_ui_version" "$fake_ui_sha256"
ram_listing="$tmp/ram-archive-listing.txt"
tar -tzf "$ram_archive" >"$ram_listing"
grep -Fqx 'llama-ram/bin/llama-cli' "$ram_listing"
grep -Fqx 'llama-ram/bin/llama-server' "$ram_listing"
grep -Fqx 'llama-ram/metadata/SHA256SUMS' "$ram_listing"
grep -Fqx 'llama-ram/share/llama-ui/dist.tar.gz' "$ram_listing"
grep -Fqx 'llama-ram/share/llama-ui/SHA256SUMS' "$ram_listing"
grep -Fqx 'llama-ram/share/llama-ui/bundle-info.txt' "$ram_listing"

cuda_archive="$tmp/artifacts/llama-cuda.tar.gz"
cuda_args=(
    "${common_make_args[@]}"
    build-cuda
    "LLAMA_CUDA_SOURCE_DIR=$tmp/source"
    "LLAMA_CUDA_BUILD_DIR=$tmp/build/cuda"
    "LLAMA_CUDA_OUTPUT_DIR=$tmp/output/cuda"
    "LLAMA_CUDA_MODEL_DIR=$tmp/models"
    "LLAMA_CUDA_ARCHIVE_PATH=$cuda_archive"
    LLAMA_CUDA_SCCACHE_DIR=
    LLAMA_CUDA_SCCACHE_SERVER_UDS=
    LLAMA_CUDA_CMAKE_GENERATOR=Unix\ Makefiles
    LLAMA_CUDA_BUILD_JOBS=2
    LLAMA_CUDA_CMAKE_C_COMPILER=/usr/bin/gcc-14
    LLAMA_CUDA_CMAKE_CXX_COMPILER=/usr/bin/g++-14
    "LLAMA_CUDA_CMAKE_CUDA_COMPILER=$fake_bin/nvcc"
    LLAMA_CUDA_CMAKE_CUDA_HOST_COMPILER=
    LLAMA_CUDA_CMAKE_C_COMPILER_LAUNCHER=
    LLAMA_CUDA_CMAKE_CXX_COMPILER_LAUNCHER=
    LLAMA_CUDA_CMAKE_CUDA_COMPILER_LAUNCHER=
    LLAMA_CUDA_ENABLE_CUDA_GLIBC_COMPAT=0
    LLAMA_CUDA_CUDA_GLIBC_HEADER=
    LLAMA_CUDA_CUDA_GLIBC_COMPAT_DIR=
    LLAMA_CUDA_GGML_NATIVE=0
    LLAMA_CUDA_ENABLE_LTO=0
    LLAMA_CUDA_ENABLE_OPENMP=0
    LLAMA_CUDA_STRIP_BINARIES=0
    LLAMA_CUDA_ENABLE_SERVER_UI=0
    LLAMA_CUDA_USE_PREBUILT_UI=1
    LLAMA_CUDA_SERVER_UI_HF_BUCKET=ggml-org/llama-ui
    "LLAMA_CUDA_SERVER_UI_VERSION=$fake_ui_version"
    "LLAMA_CUDA_SERVER_UI_SHA256=$fake_ui_sha256"
    LLAMA_CUDA_ENABLE_SERVER_UI_GZIP=1
)
run_make "$tmp/build-cuda.log" "${cuda_args[@]}"

for target in llama-cli llama-server llama-bench llama-quantize llama-gguf-split; do
    [[ -x "$tmp/output/cuda/bin/$target" ]]
done
[[ -f "$cuda_archive" ]]
grep -Fqx 'build_profile=cuda' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx 'backend=CUDA' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx 'cuda_architectures=61' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx 'server_ui=1' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx 'server_ui_build_from_source=0' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx 'server_ui_prebuilt=1' "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx "server_ui_asset_version=$fake_ui_version" "$tmp/output/cuda/metadata/build-info.txt"
grep -Fqx "server_ui_asset_sha256=$fake_ui_sha256" "$tmp/output/cuda/metadata/build-info.txt"
grep -F -- '-DGGML_CUDA=ON' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DCMAKE_CUDA_ARCHITECTURES=61' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DGGML_CUDA_NO_PEER_COPY=ON' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DGGML_CUDA_GRAPHS=OFF' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DGGML_CUDA_NCCL=OFF' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DGGML_CUDA_COMPRESSION_MODE=size' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_BUILD_UI=OFF' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
grep -F -- '-DLLAMA_USE_PREBUILT_UI=ON' "$tmp/output/cuda/metadata/cmake-command.txt" >/dev/null
assert_staged_ui_bundle "$tmp/build/cuda" "$tmp/output/cuda" "$fake_ui_version" "$fake_ui_sha256"
cuda_listing="$tmp/cuda-archive-listing.txt"
tar -tzf "$cuda_archive" >"$cuda_listing"
grep -Fqx 'llama-cuda/bin/llama-cli' "$cuda_listing"
grep -Fqx 'llama-cuda/bin/llama-server' "$cuda_listing"
grep -Fqx 'llama-cuda/metadata/SHA256SUMS' "$cuda_listing"
grep -Fqx 'llama-cuda/share/llama-ui/dist.tar.gz' "$cuda_listing"
grep -Fqx 'llama-cuda/share/llama-ui/SHA256SUMS' "$cuda_listing"
grep -Fqx 'llama-cuda/share/llama-ui/bundle-info.txt' "$cuda_listing"

first_archive_sha="$(sha256sum "$cuda_archive" | awk '{print $1}')"
cuda_package_args=("${cuda_args[@]}")
cuda_package_args[${#common_make_args[@]}]=package-cuda
run_make "$tmp/package-cuda.log" "${cuda_package_args[@]}"
second_archive_sha="$(sha256sum "$cuda_archive" | awk '{print $1}')"
[[ "$first_archive_sha" == "$second_archive_sha" ]]

cp -- "$tmp/output/cuda/share/llama-ui/dist.tar.gz" "$tmp/staged-ui-archive.backup"
printf 'tampered\n' >>"$tmp/output/cuda/share/llama-ui/dist.tar.gz"
if PATH="$fake_bin:$PATH" make -C "$ROOT_DIR" "${cuda_package_args[@]}" \
    >"$tmp/tampered-staged-ui.log" 2>&1; then
    printf 'Tampered staged UI bundle unexpectedly passed package verification\n' >&2
    exit 1
fi
grep -Fq 'Staged pinned UI bundle failed its local checksum manifest' "$tmp/tampered-staged-ui.log"
mv -- "$tmp/staged-ui-archive.backup" "$tmp/output/cuda/share/llama-ui/dist.tar.gz"

ram_offline_args=("${ram_args[@]}")
ram_offline_args[${#common_make_args[@]}]=doctor-ram
ram_offline_args+=(OFFLINE=1)
run_make "$tmp/doctor-ram-offline.log" "${ram_offline_args[@]}"
grep -Fq 'Offline server UI cache verified' "$tmp/doctor-ram-offline.log"

cold_offline_args=("${ram_offline_args[@]}")
cold_offline_args+=("LLAMA_RAM_BUILD_DIR=$tmp/build/cold")
if PATH="$fake_bin:$PATH" make -C "$ROOT_DIR" "${cold_offline_args[@]}" >"$tmp/cold-offline.log" 2>&1; then
    printf 'Cold offline profile unexpectedly passed without cached UI assets\n' >&2
    exit 1
fi
grep -Fq 'OFFLINE=1 requires the pinned server UI cache' "$tmp/cold-offline.log"

cp -- "$tmp/build/ram/tools/ui/dist.tar.gz" "$tmp/ui-archive.backup"
printf 'tampered\n' >>"$tmp/build/ram/tools/ui/dist.tar.gz"
if PATH="$fake_bin:$PATH" make -C "$ROOT_DIR" "${ram_offline_args[@]}" >"$tmp/tampered-ui.log" 2>&1; then
    printf 'Tampered cached UI archive unexpectedly passed verification\n' >&2
    exit 1
fi
grep -Fq 'does not match its downloaded checksum' "$tmp/tampered-ui.log"
mv -- "$tmp/ui-archive.backup" "$tmp/build/ram/tools/ui/dist.tar.gz"

if make -C "$ROOT_DIR" --no-print-directory info-ram ENABLE_CUDA=1 >"$tmp/invalid-ram.log" 2>&1; then
    printf 'RAM profile unexpectedly accepted ENABLE_CUDA=1\n' >&2
    exit 1
fi
grep -Fq 'ram profile must not enable a primary GPU backend' "$tmp/invalid-ram.log"

if make -C "$ROOT_DIR" --no-print-directory info-cuda LLAMA_CUDA_ENABLE_CUDA=0 >"$tmp/invalid-cuda.log" 2>&1; then
    printf 'CUDA profile unexpectedly accepted LLAMA_CUDA_ENABLE_CUDA=0\n' >&2
    exit 1
fi
grep -Fq 'cuda profile requires ENABLE_CUDA=1' "$tmp/invalid-cuda.log"

if make -C "$ROOT_DIR" --no-print-directory info-cuda \
    LLAMA_CUDA_ENABLE_SERVER_UI=1 >"$tmp/invalid-ui-mode.log" 2>&1; then
    printf 'CUDA profile unexpectedly accepted simultaneous npm and pinned prebuilt UI modes\n' >&2
    exit 1
fi
grep -Fq 'npm cannot override the pinned bundle' "$tmp/invalid-ui-mode.log"

if make -C "$ROOT_DIR" --no-print-directory info-ram \
    LLAMA_RAM_ARCHIVE_PATH=output/ram/nested.tar.gz >"$tmp/invalid-archive.log" 2>&1; then
    printf 'Profile unexpectedly accepted an archive inside OUTPUT_DIR\n' >&2
    exit 1
fi
grep -Fq 'ARCHIVE_PATH must not be inside OUTPUT_DIR' "$tmp/invalid-archive.log"

printf 'profile-builds: ok\n'
