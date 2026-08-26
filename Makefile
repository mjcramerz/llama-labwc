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
CMAKE_GENERATOR ?= auto
BUILD_JOBS ?= auto
CMAKE_C_COMPILER ?=
CMAKE_CXX_COMPILER ?=
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

export ROOT_DIR LLAMA_CPP_REPO LLAMA_CPP_REF SOURCE_DIR BUILD_DIR OUTPUT_DIR MODEL_DIR
export CMAKE_GENERATOR BUILD_JOBS CMAKE_C_COMPILER CMAKE_CXX_COMPILER BUILD_TARGETS
export GGML_NATIVE ENABLE_LTO ENABLE_CCACHE ENABLE_OPENMP ENABLE_CPU_REPACK ENABLE_LLAMAFILE ENABLE_FAST_MATH
export ENABLE_BLAS BLAS_VENDOR ENABLE_CUDA CUDA_ARCHS ENABLE_CUDA_FA ENABLE_CUDA_FA_ALL_QUANTS
export ENABLE_CUDA_GRAPHS ENABLE_CUDA_NCCL CUDA_FORCE_MMQ CUDA_FORCE_CUBLAS
export ENABLE_HIP AMDGPU_TARGETS ENABLE_HIP_GRAPHS ENABLE_HIP_RCCL ENABLE_VULKAN
export ENABLE_SYCL ENABLE_SYCL_F16 SYCL_TARGET SYCL_DEVICE_ARCH ENABLE_OPENCL ENABLE_OPENVINO ENABLE_RPC
export ENABLE_SERVER_UI USE_PREBUILT_UI ENABLE_OPENSSL ENABLE_LLGUIDANCE STRIP_BINARIES
export OFFLINE SOURCE_UPDATE FORCE_SOURCE_RESET ALLOW_EXTERNAL_DIRS EXTRA_CMAKE_ARGS EXTRA_C_FLAGS EXTRA_CXX_FLAGS
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
.PHONY: service-render service-enable service-disable service-start service-stop service-restart
.PHONY: service-status service-logs service-uninstall

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "llama.cpp host-native builder\n\nUsage:\n  make <target> [VARIABLE=value ...]\n\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nExamples:\n  make doctor\n  make build\n  make download\n  make download MODEL=qwen3-8b-q4_k_m\n  make download HF_REPO=bartowski/Llama-3.2-3B-Instruct-GGUF HF_QUANT=Q4_K_M\n  make run MODEL=qwen3.5-0.8b-q4_k_m\n  make server SERVER_MODEL=qwen3.5-0.8b-q4_k_m\n  make build ENABLE_CUDA=1 CUDA_ARCHS=auto\n  make service-enable ENABLE_USER_SERVICE=1 SERVER_MODEL=qwen3.5-0.8b-q4_k_m\n'

doctor: ## Check compilers, CMake, tools, and enabled accelerator dependencies
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

rebuild: ## Remove build products, then rebuild from scratch
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory build

verify: ## Verify staged binaries and dynamic dependencies
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/verify.sh"

info: ## Print effective build, runtime, model, and server configuration
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

distclean: ## Also remove managed llama.cpp source; preserve downloaded models
	@CONFIG_FROM_MAKE=1 "$(ROOT_DIR)/scripts/clean.sh" distclean

purge: ## Remove build/source/output/models; requires CONFIRM=YES
	@CONFIG_FROM_MAKE=1 CONFIRM="$(CONFIRM)" "$(ROOT_DIR)/scripts/clean.sh" purge
