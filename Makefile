SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Local configuration. Command-line assignments override .env, for example:
#   make build ENABLE_CUDA=1 CUDA_ARCHS=89
-include $(ROOT_DIR)/.env

LLAMA_CPP_REPO ?= https://github.com/ggml-org/llama.cpp.git
LLAMA_CPP_REF ?= b10270
SOURCE_DIR ?= .cache/llama.cpp
BUILD_DIR ?= .build/native
OUTPUT_DIR ?= output
MODEL_DIR ?= output/models
BUILD_PROFILE ?= native
ARCHIVE_PATH ?=
CMAKE_GENERATOR ?= auto
TOOLCHAIN_PATH_PREFIX ?= /usr/bin:/bin
BUILD_JOBS ?= auto
CMAKE_C_COMPILER ?=
CMAKE_CXX_COMPILER ?=
CMAKE_CUDA_COMPILER ?=
CMAKE_CUDA_HOST_COMPILER ?=
CMAKE_C_COMPILER_LAUNCHER ?=
CMAKE_CXX_COMPILER_LAUNCHER ?=
CMAKE_CUDA_COMPILER_LAUNCHER ?=
CMAKE_C_FLAGS ?= -B/usr/bin
CMAKE_CXX_FLAGS ?= -B/usr/bin
CMAKE_CUDA_FLAGS ?= -Xcompiler=-B/usr/bin
SCCACHE_DIR ?=
SCCACHE_SERVER_UDS ?=
BUILD_TARGETS ?= llama-cli llama-server llama-bench llama-quantize llama-gguf-split
GGML_NATIVE ?= 1
ENABLE_LTO ?= 1
ENABLE_CCACHE ?= 1
ENABLE_OPENMP ?= 1
ENABLE_CPU_REPACK ?= 1
ENABLE_LLAMAFILE ?= 1
ENABLE_FAST_MATH ?= 0
ENABLE_BLAS ?= 0
BLAS_VENDOR ?= OpenBLAS
ENABLE_CUDA ?= 0
CUDA_ARCHS ?= auto
ENABLE_CUDA_FA ?= 1
ENABLE_CUDA_FA_ALL_QUANTS ?= 0
ENABLE_CUDA_GRAPHS ?= 1
ENABLE_CUDA_NCCL ?= 0
CUDA_FORCE_MMQ ?= 0
CUDA_FORCE_CUBLAS ?= 0
CUDA_NO_PEER_COPY ?= 0
CUDA_NO_VMM ?= 0
CUDA_COMPRESSION_MODE ?= size
ENABLE_CUDA_GLIBC_COMPAT ?= 0
CUDA_GLIBC_HEADER ?=
CUDA_GLIBC_COMPAT_DIR ?=
ENABLE_HIP ?= 0
AMDGPU_TARGETS ?= auto
ENABLE_HIP_GRAPHS ?= 1
ENABLE_HIP_RCCL ?= 0
ENABLE_VULKAN ?= 0
ENABLE_SYCL ?= 0
ENABLE_SYCL_F16 ?= 0
SYCL_TARGET ?= INTEL
SYCL_DEVICE_ARCH ?=
ENABLE_OPENCL ?= 0
ENABLE_OPENVINO ?= 0
ENABLE_RPC ?= 0
ENABLE_SERVER_UI ?= 0
USE_PREBUILT_UI ?= 0
SERVER_UI_HF_BUCKET ?= ggml-org/llama-ui
SERVER_UI_VERSION ?=
SERVER_UI_SHA256 ?=
ENABLE_SERVER_UI_GZIP ?= 1
ENABLE_OPENSSL ?= 0
ENABLE_LLGUIDANCE ?= 0
STRIP_BINARIES ?= 1
OFFLINE ?= 0
SOURCE_UPDATE ?= 0
FORCE_SOURCE_RESET ?= 0
ALLOW_EXTERNAL_DIRS ?= 0
EXTRA_CMAKE_ARGS ?=
EXTRA_C_FLAGS ?=
EXTRA_CXX_FLAGS ?=
EXTRA_CUDA_FLAGS ?=

# Profile fallbacks keep `make build-ram` and `make build-cuda` functional even
# when the ignored local .env has not been created yet.
LLAMA_RAM_SOURCE_DIR ?= .cache/llama.cpp
LLAMA_RAM_BUILD_DIR ?= .build/ram
LLAMA_RAM_OUTPUT_DIR ?= output/ram
LLAMA_RAM_MODEL_DIR ?= output/models
LLAMA_RAM_ARCHIVE_PATH ?= output/llama-ram.tar.gz
LLAMA_RAM_SCCACHE_DIR ?= .cache/sccache/ram
LLAMA_RAM_SCCACHE_SERVER_UDS ?= .cache/sccache/ram/server.sock
LLAMA_RAM_CMAKE_GENERATOR ?= auto
LLAMA_RAM_BUILD_JOBS ?= auto
LLAMA_RAM_CMAKE_C_COMPILER ?= /usr/bin/gcc-14
LLAMA_RAM_CMAKE_CXX_COMPILER ?= /usr/bin/g++-14
LLAMA_RAM_CMAKE_CUDA_COMPILER ?=
LLAMA_RAM_CMAKE_CUDA_HOST_COMPILER ?=
LLAMA_RAM_CMAKE_C_COMPILER_LAUNCHER ?= sccache
LLAMA_RAM_CMAKE_CXX_COMPILER_LAUNCHER ?= sccache
LLAMA_RAM_CMAKE_CUDA_COMPILER_LAUNCHER ?=
LLAMA_RAM_CMAKE_C_FLAGS ?= -B/usr/bin
LLAMA_RAM_CMAKE_CXX_FLAGS ?= -B/usr/bin
LLAMA_RAM_CMAKE_CUDA_FLAGS ?=
LLAMA_RAM_GGML_NATIVE ?= 1
LLAMA_RAM_ENABLE_LTO ?= 1
LLAMA_RAM_ENABLE_CCACHE ?= 0
LLAMA_RAM_ENABLE_OPENMP ?= 1
LLAMA_RAM_ENABLE_CPU_REPACK ?= 1
LLAMA_RAM_ENABLE_LLAMAFILE ?= 1
LLAMA_RAM_ENABLE_FAST_MATH ?= 0
LLAMA_RAM_ENABLE_BLAS ?= 0
LLAMA_RAM_BLAS_VENDOR ?= OpenBLAS
LLAMA_RAM_ENABLE_CUDA ?= 0
LLAMA_RAM_CUDA_ARCHS ?= auto
LLAMA_RAM_ENABLE_CUDA_FA ?= 0
LLAMA_RAM_ENABLE_CUDA_FA_ALL_QUANTS ?= 0
LLAMA_RAM_ENABLE_CUDA_GRAPHS ?= 0
LLAMA_RAM_ENABLE_CUDA_NCCL ?= 0
LLAMA_RAM_CUDA_FORCE_MMQ ?= 0
LLAMA_RAM_CUDA_FORCE_CUBLAS ?= 0
LLAMA_RAM_CUDA_NO_PEER_COPY ?= 0
LLAMA_RAM_CUDA_NO_VMM ?= 0
LLAMA_RAM_CUDA_COMPRESSION_MODE ?= size
LLAMA_RAM_ENABLE_CUDA_GLIBC_COMPAT ?= 0
LLAMA_RAM_CUDA_GLIBC_HEADER ?=
LLAMA_RAM_CUDA_GLIBC_COMPAT_DIR ?=
LLAMA_RAM_ENABLE_HIP ?= 0
LLAMA_RAM_AMDGPU_TARGETS ?= auto
LLAMA_RAM_ENABLE_HIP_GRAPHS ?= 0
LLAMA_RAM_ENABLE_HIP_RCCL ?= 0
LLAMA_RAM_ENABLE_VULKAN ?= 0
LLAMA_RAM_ENABLE_SYCL ?= 0
LLAMA_RAM_ENABLE_SYCL_F16 ?= 0
LLAMA_RAM_SYCL_TARGET ?= INTEL
LLAMA_RAM_SYCL_DEVICE_ARCH ?=
LLAMA_RAM_ENABLE_OPENCL ?= 0
LLAMA_RAM_ENABLE_OPENVINO ?= 0
LLAMA_RAM_ENABLE_RPC ?= 0
LLAMA_RAM_ENABLE_SERVER_UI ?= 0
LLAMA_RAM_USE_PREBUILT_UI ?= 1
LLAMA_RAM_SERVER_UI_HF_BUCKET ?= ggml-org/llama-ui
LLAMA_RAM_SERVER_UI_VERSION ?= b10270
LLAMA_RAM_SERVER_UI_SHA256 ?= c63b205dc7b5574a3d8f2d7793d1d1bbad886a81a14a04c591d536b05ac4d8ba
LLAMA_RAM_ENABLE_SERVER_UI_GZIP ?= 1
LLAMA_RAM_ENABLE_OPENSSL ?= 0
LLAMA_RAM_ENABLE_LLGUIDANCE ?= 0
LLAMA_RAM_STRIP_BINARIES ?= 1
LLAMA_RAM_EXTRA_CMAKE_ARGS ?=
LLAMA_RAM_EXTRA_C_FLAGS ?=
LLAMA_RAM_EXTRA_CXX_FLAGS ?=
LLAMA_RAM_EXTRA_CUDA_FLAGS ?=

LLAMA_CUDA_SOURCE_DIR ?= .cache/llama.cpp
LLAMA_CUDA_BUILD_DIR ?= .build/cuda
LLAMA_CUDA_OUTPUT_DIR ?= output/cuda
LLAMA_CUDA_MODEL_DIR ?= output/models
LLAMA_CUDA_ARCHIVE_PATH ?= output/llama-cuda.tar.gz
LLAMA_CUDA_SCCACHE_DIR ?= .cache/sccache/cuda
LLAMA_CUDA_SCCACHE_SERVER_UDS ?= .cache/sccache/cuda/server.sock
LLAMA_CUDA_CMAKE_GENERATOR ?= auto
LLAMA_CUDA_BUILD_JOBS ?= auto
LLAMA_CUDA_CMAKE_C_COMPILER ?= /usr/bin/gcc-14
LLAMA_CUDA_CMAKE_CXX_COMPILER ?= /usr/bin/g++-14
LLAMA_CUDA_CMAKE_CUDA_COMPILER ?= /usr/local/cuda-12.8/bin/nvcc
LLAMA_CUDA_CMAKE_CUDA_HOST_COMPILER ?= /usr/bin/g++-14
LLAMA_CUDA_CMAKE_C_COMPILER_LAUNCHER ?= sccache
LLAMA_CUDA_CMAKE_CXX_COMPILER_LAUNCHER ?= sccache
LLAMA_CUDA_CMAKE_CUDA_COMPILER_LAUNCHER ?=
LLAMA_CUDA_CMAKE_C_FLAGS ?= -B/usr/bin
LLAMA_CUDA_CMAKE_CXX_FLAGS ?= -B/usr/bin
LLAMA_CUDA_CMAKE_CUDA_FLAGS ?= -Xcompiler=-B/usr/bin
LLAMA_CUDA_GGML_NATIVE ?= 1
LLAMA_CUDA_ENABLE_LTO ?= 1
LLAMA_CUDA_ENABLE_CCACHE ?= 0
LLAMA_CUDA_ENABLE_OPENMP ?= 1
LLAMA_CUDA_ENABLE_CPU_REPACK ?= 1
LLAMA_CUDA_ENABLE_LLAMAFILE ?= 1
LLAMA_CUDA_ENABLE_FAST_MATH ?= 0
LLAMA_CUDA_ENABLE_BLAS ?= 0
LLAMA_CUDA_BLAS_VENDOR ?= OpenBLAS
LLAMA_CUDA_ENABLE_CUDA ?= 1
LLAMA_CUDA_CUDA_ARCHS ?= 61
LLAMA_CUDA_ENABLE_CUDA_FA ?= 1
LLAMA_CUDA_ENABLE_CUDA_FA_ALL_QUANTS ?= 0
LLAMA_CUDA_ENABLE_CUDA_GRAPHS ?= 0
LLAMA_CUDA_ENABLE_CUDA_NCCL ?= 0
LLAMA_CUDA_CUDA_FORCE_MMQ ?= 0
LLAMA_CUDA_CUDA_FORCE_CUBLAS ?= 0
LLAMA_CUDA_CUDA_NO_PEER_COPY ?= 1
LLAMA_CUDA_CUDA_NO_VMM ?= 0
LLAMA_CUDA_CUDA_COMPRESSION_MODE ?= size
LLAMA_CUDA_ENABLE_CUDA_GLIBC_COMPAT ?= 1
LLAMA_CUDA_CUDA_GLIBC_HEADER ?= /usr/local/cuda-12.8/targets/x86_64-linux/include/crt/math_functions.h
LLAMA_CUDA_CUDA_GLIBC_COMPAT_DIR ?= .cache/cuda-compat/12.8
LLAMA_CUDA_ENABLE_HIP ?= 0
LLAMA_CUDA_AMDGPU_TARGETS ?= auto
LLAMA_CUDA_ENABLE_HIP_GRAPHS ?= 0
LLAMA_CUDA_ENABLE_HIP_RCCL ?= 0
LLAMA_CUDA_ENABLE_VULKAN ?= 0
LLAMA_CUDA_ENABLE_SYCL ?= 0
LLAMA_CUDA_ENABLE_SYCL_F16 ?= 0
LLAMA_CUDA_SYCL_TARGET ?= INTEL
LLAMA_CUDA_SYCL_DEVICE_ARCH ?=
LLAMA_CUDA_ENABLE_OPENCL ?= 0
LLAMA_CUDA_ENABLE_OPENVINO ?= 0
LLAMA_CUDA_ENABLE_RPC ?= 0
LLAMA_CUDA_ENABLE_SERVER_UI ?= 0
LLAMA_CUDA_USE_PREBUILT_UI ?= 1
LLAMA_CUDA_SERVER_UI_HF_BUCKET ?= ggml-org/llama-ui
LLAMA_CUDA_SERVER_UI_VERSION ?= b10270
LLAMA_CUDA_SERVER_UI_SHA256 ?= c63b205dc7b5574a3d8f2d7793d1d1bbad886a81a14a04c591d536b05ac4d8ba
LLAMA_CUDA_ENABLE_SERVER_UI_GZIP ?= 1
LLAMA_CUDA_ENABLE_OPENSSL ?= 0
LLAMA_CUDA_ENABLE_LLGUIDANCE ?= 0
LLAMA_CUDA_STRIP_BINARIES ?= 1
LLAMA_CUDA_EXTRA_CMAKE_ARGS ?=
LLAMA_CUDA_EXTRA_C_FLAGS ?=
LLAMA_CUDA_EXTRA_CXX_FLAGS ?=
LLAMA_CUDA_EXTRA_CUDA_FLAGS ?=

RAM_PROFILE_TARGETS := build-ram doctor-ram info-ram verify-ram package-ram clean-ram
CUDA_PROFILE_TARGETS := build-cuda doctor-cuda info-cuda verify-cuda package-cuda clean-cuda

PROFILE_VARIABLES := SOURCE_DIR BUILD_DIR OUTPUT_DIR MODEL_DIR ARCHIVE_PATH \
	SCCACHE_DIR SCCACHE_SERVER_UDS CMAKE_GENERATOR BUILD_JOBS CMAKE_C_COMPILER \
	CMAKE_CXX_COMPILER CMAKE_CUDA_COMPILER CMAKE_CUDA_HOST_COMPILER \
	CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER CMAKE_CUDA_COMPILER_LAUNCHER \
	CMAKE_C_FLAGS CMAKE_CXX_FLAGS CMAKE_CUDA_FLAGS GGML_NATIVE ENABLE_LTO ENABLE_CCACHE \
	ENABLE_OPENMP ENABLE_CPU_REPACK ENABLE_LLAMAFILE ENABLE_FAST_MATH ENABLE_BLAS BLAS_VENDOR \
	ENABLE_CUDA CUDA_ARCHS ENABLE_CUDA_FA ENABLE_CUDA_FA_ALL_QUANTS ENABLE_CUDA_GRAPHS \
	ENABLE_CUDA_NCCL CUDA_FORCE_MMQ CUDA_FORCE_CUBLAS CUDA_NO_PEER_COPY CUDA_NO_VMM \
	CUDA_COMPRESSION_MODE ENABLE_CUDA_GLIBC_COMPAT CUDA_GLIBC_HEADER CUDA_GLIBC_COMPAT_DIR \
	ENABLE_HIP AMDGPU_TARGETS ENABLE_HIP_GRAPHS ENABLE_HIP_RCCL ENABLE_VULKAN ENABLE_SYCL \
	ENABLE_SYCL_F16 SYCL_TARGET SYCL_DEVICE_ARCH ENABLE_OPENCL ENABLE_OPENVINO ENABLE_RPC \
	ENABLE_SERVER_UI USE_PREBUILT_UI SERVER_UI_HF_BUCKET SERVER_UI_VERSION SERVER_UI_SHA256 \
	ENABLE_SERVER_UI_GZIP ENABLE_OPENSSL ENABLE_LLGUIDANCE STRIP_BINARIES \
	EXTRA_CMAKE_ARGS EXTRA_C_FLAGS EXTRA_CXX_FLAGS EXTRA_CUDA_FLAGS

$(RAM_PROFILE_TARGETS): BUILD_PROFILE := ram
$(CUDA_PROFILE_TARGETS): BUILD_PROFILE := cuda

define bind_ram_profile_variable
$(RAM_PROFILE_TARGETS): $(1) := $$(LLAMA_RAM_$(1))
endef
$(foreach variable,$(PROFILE_VARIABLES),$(eval $(call bind_ram_profile_variable,$(variable))))

define bind_cuda_profile_variable
$(CUDA_PROFILE_TARGETS): $(1) := $$(LLAMA_CUDA_$(1))
endef
$(foreach variable,$(PROFILE_VARIABLES),$(eval $(call bind_cuda_profile_variable,$(variable))))

MODEL ?=
HF_REPO ?=
HF_FILE ?=
HF_QUANT ?= Q4_K_M
HF_REVISION ?= main
HF_TOKEN ?=
HF_API_BASE ?= https://huggingface.co/api/models
HF_DOWNLOAD_BASE ?= https://huggingface.co
DOWNLOAD_MMPROJ ?= 0
VERIFY_REMOTE_SHA256 ?= 1
STRICT_CHECKSUM ?= 0
STRICT_RESOURCES ?= 0
FORCE_DOWNLOAD ?= 0
DOWNLOAD_RETRIES ?= 4
DOWNLOAD_CONNECT_TIMEOUT ?= 20

PROMPT ?= Explain why a host-native llama.cpp build can improve local inference speed.
ARGS ?=
RUNTIME_THREADS ?= auto
RUNTIME_THREADS_BATCH ?= auto
GPU_LAYERS ?= auto
RUNTIME_DEVICE ?=
CTX_SIZE ?= 8192

ENABLE_USER_SERVICE ?= 0
SERVICE_NAME ?= llama-server-native
SERVICE_AUTOSTART ?= 1
SERVICE_START_NOW ?= 1
SERVICE_RESTART ?= on-failure
SERVICE_RESTART_SEC ?= 3
SERVICE_TIMEOUT_STOP_SEC ?= 90
SERVER_MODEL ?= qwen3.5-0.8b-q4_k_m
SERVER_MODEL_PATH ?=
SERVER_ALIAS ?= local-model
SERVER_HOST ?= 127.0.0.1
SERVER_PORT ?= 8080
SERVER_THREADS ?= auto
SERVER_THREADS_BATCH ?= auto
SERVER_CTX_SIZE ?= 8192
SERVER_PARALLEL ?= 1
SERVER_GPU_LAYERS ?= auto
SERVER_DEVICE ?=
SERVER_FLASH_ATTN ?= auto
SERVER_LOAD_MODE ?= mmap
SERVER_KEEP_MODEL_LOADED ?= 1
SERVER_SLEEP_IDLE_SECONDS ?= 300
SERVER_PIN_MODEL ?= 0
SERVER_FULL_GPU_OFFLOAD ?= 0
SERVER_CACHE_TYPE_K ?= f16
SERVER_CACHE_TYPE_V ?= f16
SERVER_CONT_BATCHING ?= 1
SERVER_METRICS ?= 0
SERVER_EMBEDDINGS ?= 0
SERVER_RERANKING ?= 0
SERVER_JINJA ?= 1
SERVER_API_KEY ?=
SERVER_TIMEOUT ?= 3600
SERVER_EXTRA_ARGS ?=

export ROOT_DIR LLAMA_CPP_REPO LLAMA_CPP_REF SOURCE_DIR BUILD_DIR OUTPUT_DIR MODEL_DIR BUILD_PROFILE ARCHIVE_PATH
export CMAKE_GENERATOR TOOLCHAIN_PATH_PREFIX BUILD_JOBS CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_CUDA_COMPILER CMAKE_CUDA_HOST_COMPILER
export CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER CMAKE_CUDA_COMPILER_LAUNCHER
export CMAKE_C_FLAGS CMAKE_CXX_FLAGS CMAKE_CUDA_FLAGS SCCACHE_DIR SCCACHE_SERVER_UDS BUILD_TARGETS
export GGML_NATIVE ENABLE_LTO ENABLE_CCACHE ENABLE_OPENMP ENABLE_CPU_REPACK ENABLE_LLAMAFILE ENABLE_FAST_MATH
export ENABLE_BLAS BLAS_VENDOR ENABLE_CUDA CUDA_ARCHS ENABLE_CUDA_FA ENABLE_CUDA_FA_ALL_QUANTS
export ENABLE_CUDA_GRAPHS ENABLE_CUDA_NCCL CUDA_FORCE_MMQ CUDA_FORCE_CUBLAS CUDA_NO_PEER_COPY CUDA_NO_VMM
export CUDA_COMPRESSION_MODE ENABLE_CUDA_GLIBC_COMPAT CUDA_GLIBC_HEADER CUDA_GLIBC_COMPAT_DIR
export ENABLE_HIP AMDGPU_TARGETS ENABLE_HIP_GRAPHS ENABLE_HIP_RCCL ENABLE_VULKAN
export ENABLE_SYCL ENABLE_SYCL_F16 SYCL_TARGET SYCL_DEVICE_ARCH ENABLE_OPENCL ENABLE_OPENVINO ENABLE_RPC
export ENABLE_SERVER_UI USE_PREBUILT_UI SERVER_UI_HF_BUCKET SERVER_UI_VERSION SERVER_UI_SHA256
export ENABLE_SERVER_UI_GZIP ENABLE_OPENSSL ENABLE_LLGUIDANCE STRIP_BINARIES
export OFFLINE SOURCE_UPDATE FORCE_SOURCE_RESET ALLOW_EXTERNAL_DIRS EXTRA_CMAKE_ARGS EXTRA_C_FLAGS EXTRA_CXX_FLAGS EXTRA_CUDA_FLAGS
export MODEL HF_REPO HF_FILE HF_QUANT HF_REVISION HF_TOKEN HF_API_BASE HF_DOWNLOAD_BASE DOWNLOAD_MMPROJ
export VERIFY_REMOTE_SHA256 STRICT_CHECKSUM STRICT_RESOURCES FORCE_DOWNLOAD DOWNLOAD_RETRIES DOWNLOAD_CONNECT_TIMEOUT
export PROMPT RUN_ARGS RUNTIME_THREADS RUNTIME_THREADS_BATCH GPU_LAYERS RUNTIME_DEVICE CTX_SIZE
export ENABLE_USER_SERVICE SERVICE_NAME SERVICE_AUTOSTART SERVICE_START_NOW SERVICE_RESTART
export SERVICE_RESTART_SEC SERVICE_TIMEOUT_STOP_SEC SERVER_MODEL SERVER_MODEL_PATH SERVER_ALIAS SERVER_HOST SERVER_PORT
export SERVER_THREADS SERVER_THREADS_BATCH SERVER_CTX_SIZE SERVER_PARALLEL SERVER_GPU_LAYERS SERVER_DEVICE
export SERVER_FLASH_ATTN SERVER_LOAD_MODE SERVER_KEEP_MODEL_LOADED SERVER_SLEEP_IDLE_SECONDS SERVER_PIN_MODEL
export SERVER_FULL_GPU_OFFLOAD SERVER_CACHE_TYPE_K SERVER_CACHE_TYPE_V SERVER_CONT_BATCHING SERVER_METRICS
export SERVER_EMBEDDINGS SERVER_RERANKING SERVER_JINJA SERVER_API_KEY SERVER_TIMEOUT SERVER_EXTRA_ARGS

.PHONY: help doctor source update-source configure build rebuild verify info print-config list-devices
.PHONY: models download model-path run server bench test clean distclean purge
.PHONY: build-ram build-cuda doctor-ram doctor-cuda info-ram info-cuda
.PHONY: verify-ram verify-cuda package-ram package-cuda clean-ram clean-cuda
.PHONY: service-render service-enable service-disable service-start service-stop service-restart
.PHONY: service-status service-logs service-uninstall

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "llama.cpp host-native builder\n\nUsage:\n  make <target> [VARIABLE=value ...]\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nExamples:\n  make build-ram\n  make build-cuda\n  make info-cuda\n  make download\n  make download MODEL=qwen3-8b-q4_k_m\n  make download HF_REPO=bartowski/Llama-3.2-3B-Instruct-GGUF HF_QUANT=Q4_K_M\n  make run MODEL=qwen3.5-0.8b-q4_k_m\n  make server SERVER_MODEL=qwen3.5-0.8b-q4_k_m\n  make service-enable ENABLE_USER_SERVICE=1 SERVER_MODEL=qwen3.5-0.8b-q4_k_m\n'

doctor: ## Check compilers, CMake, tools, and enabled accelerator dependencies
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"

doctor-ram: ## Check the CPU/RAM profile toolchain and sccache paths
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"

doctor-cuda: ## Check the Quadro P520 sm_61 CUDA toolchain and compatibility overlay
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"

source: ## Fetch the configured llama.cpp source ref without installing it
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/source.sh"

update-source: ## Force-refresh the configured source ref
	@CONFIG_FROM_MAKE=1 SOURCE_UPDATE=1 "$(ROOT_DIR)/scripts/source.sh"

configure: ## Check, fetch source, and configure the host-native Release build
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/source.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/configure.sh"

build: ## Compile selected llama.cpp binaries and stage them under OUTPUT_DIR
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/source.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/configure.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/build.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"

build-ram: ## Build CPU/RAM binaries and create llama-ram.tar.gz
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/source.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/configure.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/build.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/package.sh"

build-cuda: ## Build Quadro P520 sm_61 CUDA binaries and create llama-cuda.tar.gz
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/doctor.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/source.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/configure.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/build.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/package.sh"

rebuild: ## Remove build products, then rebuild from scratch
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory build

verify: ## Verify staged binaries and dynamic dependencies
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"

verify-ram: ## Verify staged CPU/RAM binaries and checksums
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"

verify-cuda: ## Verify staged CUDA binaries and checksums
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"

package-ram: ## Recreate llama-ram.tar.gz from verified staged binaries
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/package.sh"

package-cuda: ## Recreate llama-cuda.tar.gz from verified staged binaries
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/package.sh"

info: ## Print effective build, runtime, model, and server configuration
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/print-config.sh"

info-ram: ## Print the resolved CPU/RAM profile
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/print-config.sh"

info-cuda: ## Print the resolved Quadro P520 CUDA profile
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/print-config.sh"

print-config: info ## Alias for make info

list-devices: ## Ask the staged CLI to list detected compute devices
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/list-devices.sh"

models: ## Print the curated GGUF model/resource table
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/download-model.sh" --list

download: ## Select a curated GGUF model, or use MODEL/HF_REPO/HF_FILE
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/download-model.sh"

model-path: ## Resolve a downloaded model ID/path and print its absolute path
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/model-path.sh"

run: ## Run llama-cli with a downloaded model
	@CONFIG_FROM_MAKE=1 RUN_ARGS="$(ARGS)" "$(ROOT_DIR)/scripts/run.sh"

server: ## Run llama-server in the foreground using SERVER_* settings
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/server-launch.sh"

bench: ## Run llama-bench with MODEL and optional ARGS
	@CONFIG_FROM_MAKE=1 RUN_ARGS="$(ARGS)" "$(ROOT_DIR)/scripts/bench.sh"

service-render: ## Render a rootless systemd user unit under OUTPUT_DIR/systemd
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" render

service-enable: ## Install/enable the user unit; requires ENABLE_USER_SERVICE=1
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" enable

service-disable: ## Disable and stop the user unit, preserving its unit file
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" disable

service-start: ## Start the configured user llama-server service
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" start

service-stop: ## Stop the configured user llama-server service
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" stop

service-restart: ## Restart the configured user llama-server service
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" restart

service-status: ## Show service state and recent status information
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" status

service-logs: ## Follow user-service logs from journald
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" logs

service-uninstall: ## Disable and remove only the generated user unit
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/service.sh" uninstall

test: ## Run syntax, manifest, downloader, build-wrapper, and service tests
	@"$(ROOT_DIR)/tests/run.sh"

clean: ## Remove CMake products and staged binaries; preserve source and models
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/clean.sh" build

clean-ram: ## Remove RAM build/staged binaries; preserve source, models, cache, and archive
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/clean.sh" build

clean-cuda: ## Remove CUDA build/staged binaries; preserve source, models, cache, and archive
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/clean.sh" build

distclean: ## Also remove managed llama.cpp source; preserve downloaded models
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/clean.sh" distclean

purge: ## Remove build/source/output/models; requires CONFIRM=YES
	@CONFIG_FROM_MAKE=1 CONFIRM="$(CONFIRM)" "$(ROOT_DIR)/scripts/clean.sh" purge
