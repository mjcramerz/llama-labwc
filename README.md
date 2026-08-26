# llama.cpp host-native builder

A Debian/Linux build wrapper for compiling selected `llama.cpp` tools from source,
staging them locally, downloading verified GGUF models, and optionally running a
persistent rootless `llama-server` as a systemd user service.

The project deliberately does **not** run `cmake --install`, copy files into
`/usr`, or require root for normal operation. Source, build products, binaries,
models, metadata, and generated service files remain inside this repository by
default.

> **Model-format correction**
>
> Whisper names such as `tiny.en`, `large-v3-turbo`, and Distil-Whisper are
> speech-transcription models for `whisper.cpp`; they cannot be loaded by
> `llama.cpp`. This repository therefore provides a curated **GGUF LLM/VLM and
> embedding-model** catalog. Any other compatible Hugging Face GGUF repository
> can be selected through `HF_REPO`, `HF_QUANT`, or `HF_FILE`.

## Quick start

Install a CPU build toolchain on Debian:

```bash
sudo apt-get update
sudo apt-get install --yes \
    build-essential cmake ninja-build git curl ca-certificates python3 \
    pkg-config ccache
```

Then build and choose a model:

```bash
make doctor
make build
make download
```

Run the local CLI:

```bash
make run MODEL=qwen3.5-0.8b-q4_k_m \
    PROMPT='Explain virtual memory in three paragraphs.'
```

Or run the OpenAI-compatible HTTP server in the foreground:

```bash
make server SERVER_MODEL=qwen3.5-0.8b-q4_k_m
```

Generated files are staged under:

```text
.cache/llama.cpp/               pinned upstream source checkout
.build/native/                  CMake build tree
output/bin/llama-cli            staged CLI
output/bin/llama-server         staged HTTP server
output/bin/llama-bench          staged benchmark tool
output/bin/llama-quantize       staged GGUF quantizer
output/bin/llama-gguf-split     staged split/join utility
output/models/<model-id>/       downloaded GGUF files and provenance
output/metadata/                build command, commit, hashes, dependencies
output/systemd/                 generated user-service unit and private config
```

Labwc requires no special integration: all produced programs are ordinary
command-line applications and are independent of the active Wayland compositor.

## Make targets

| Target | Purpose |
|---|---|
| `make doctor` | Validate the host compiler, CMake, native flags, and enabled backend dependencies. |
| `make source` | Fetch the pinned upstream ref into the managed source directory. |
| `make configure` | Generate a host-native Release CMake build tree. |
| `make build` | Compile and stage configured tools under `output/bin`. |
| `make verify` | Check executable size, launchability, and unresolved shared libraries. |
| `make info` | Print effective configuration with secrets redacted. |
| `make list-devices` | Ask the staged CLI to enumerate compute devices. |
| `make models` | Print the curated GGUF/resource table. |
| `make download` | Interactively select a model or resolve explicit Hugging Face settings. |
| `make model-path MODEL=...` | Print the primary local GGUF path. |
| `make run` | Run `llama-cli` with sensible host thread defaults. |
| `make bench` | Run `llama-bench` against a local model. |
| `make server` | Run `llama-server` in the foreground. |
| `make service-render` | Generate, but do not install, a systemd user unit. |
| `make service-enable` | Explicitly install/enable the rootless user service. |
| `make service-status` / `service-logs` | Inspect the user service. |
| `make service-uninstall` | Stop and remove only the generated user unit. |
| `make clean` | Remove build products and staged executables; preserve source/models. |
| `make distclean` | Also remove managed source; preserve models. |
| `make purge CONFIRM=YES` | Remove all managed source, builds, output, and models. |
| `make test` | Run the offline integration suite. |

## Host-only optimization policy

The default CPU profile is intentionally non-portable:

```text
CMAKE_BUILD_TYPE=Release
-O3 -DNDEBUG
GGML_NATIVE=ON
GGML_LTO=ON
GGML_OPENMP=ON
GGML_CPU_REPACK=ON
GGML_LLAMAFILE=ON
```

The wrapper also explicitly adds architecture tuning:

```text
x86/x86-64:  -march=native -mtune=native
ARM/AArch64: -mcpu=native
POWER:       -mcpu=native -mtune=native
RISC-V:      -march=native -mtune=native
```

This lets the compiler use instruction sets exposed by the current processor.
The resulting binaries may terminate with `Illegal instruction` on a different
or older CPU. Rebuild on the destination host, or set `GGML_NATIVE=0` when
portability is more important than host-specific optimization.

`ENABLE_FAST_MATH=0` is conservative by default. Set it to `1` only after
accepting the altered floating-point semantics and benchmarking the workload;
it is not treated as an unconditional performance improvement.

The default build is statically linked against the selected GGML backends as
far as the upstream build permits (`BUILD_SHARED_LIBS=OFF` and
`GGML_BACKEND_DL=OFF`). External runtime libraries such as CUDA, HIP, Vulkan,
OpenMP, OpenSSL, or oneAPI remain dynamically provided by their normal vendor
packages.

## Build configuration

Edit `.env`, copy values from `.env.example`, or override any setting on the
Make command line. Command-line values take precedence:

```bash
make clean
make build ENABLE_BLAS=1 BLAS_VENDOR=OpenBLAS
```

Important defaults:

```dotenv
LLAMA_CPP_REF=b10270
GGML_NATIVE=1
ENABLE_LTO=1
ENABLE_OPENMP=1
ENABLE_CPU_REPACK=1
ENABLE_FAST_MATH=0
```

The default staged tools are `llama-cli`, `llama-server`, `llama-bench`,
`llama-quantize`, and `llama-gguf-split`. Because `.env` is intentionally
readable by both GNU Make and POSIX-like shells, override the space-separated
target list on the Make command line rather than placing it in `.env`:

```bash
make build BUILD_TARGETS='llama-cli llama-server llama-bench'
```

The source manager records the exact fetched commit. With an existing stamped
checkout, normal builds reuse that commit without touching the network.
`make update-source` explicitly refreshes the configured ref. `OFFLINE=1`
forbids source/model network access and succeeds only when all required local
material is already present.

### CPU with OpenBLAS

```bash
sudo apt-get install --yes libopenblas-dev
make clean
make build ENABLE_BLAS=1 BLAS_VENDOR=OpenBLAS
```

BLAS commonly helps prompt and large-batch processing more than token-by-token
generation. Benchmark both configurations on the actual workload.

### NVIDIA CUDA

Install a driver and CUDA toolkit appropriate for the host, then:

```bash
make clean
make build ENABLE_CUDA=1 CUDA_ARCHS=auto
```

`CUDA_ARCHS=auto` queries attached NVIDIA devices and compiles only their
compute capabilities. An explicit example is `CUDA_ARCHS=89`. The defaults also
enable CUDA Flash Attention and CUDA graphs while leaving NCCL disabled.

### AMD ROCm/HIP

After installing and initializing a supported ROCm toolchain:

```bash
make clean
make build ENABLE_HIP=1 AMDGPU_TARGETS=auto
```

The wrapper uses `rocm_agent_enumerator` or `rocminfo` to select only local
`gfx*` targets. An explicit example is `AMDGPU_TARGETS=gfx1100`.

### Vulkan

```bash
sudo apt-get install --yes libvulkan-dev glslc vulkan-tools
make clean
make build ENABLE_VULKAN=1
```

A working vendor Vulkan driver is required at runtime. Vulkan is a useful
cross-vendor option where CUDA, ROCm, or SYCL is unsuitable.

### Intel oneAPI/SYCL

Initialize the oneAPI environment so `icx` and `icpx` are visible, then:

```bash
make clean
make build ENABLE_SYCL=1 SYCL_TARGET=INTEL
```

`SYCL_DEVICE_ARCH` can pin a specific device architecture where required.

### OpenCL and OpenVINO

OpenCL:

```bash
sudo apt-get install --yes ocl-icd-opencl-dev clinfo
make clean
make build ENABLE_OPENCL=1
```

OpenVINO is an additional backend and requires an initialized OpenVINO CMake
environment:

```bash
make clean
make build ENABLE_OPENVINO=1
```

Enable at most one primary GPU backend among CUDA, HIP, Vulkan, SYCL, and
OpenCL in a build directory. The wrapper rejects conflicting combinations.

## GGUF model catalog and downloader

Display the complete local catalog:

```bash
make models
```

The table reports task, family, total and active parameters, quantization,
approximate weight size, estimated minimum/recommended RAM, approximate VRAM
for full weight offload, recommended CPU cores, advertised context, license,
and notes. These are desktop planning estimates, not upstream guarantees.
Context/KV cache, batch size, parallel slots, multimodal projection weights,
runtime buffers, and backend scratch space can materially increase memory use.

Interactive selection:

```bash
make download
```

Non-interactive catalog selection:

```bash
make download MODEL=qwen3-8b-q4_k_m
make download MODEL=phi4-mini-instruct-q4_k_m
make download MODEL=qwen3-embedding-0.6b-q8_0
```

Any compatible Hugging Face GGUF repository:

```bash
make download \
    HF_REPO=bartowski/Llama-3.2-3B-Instruct-GGUF \
    HF_QUANT=Q4_K_M
```

Or select an exact repository path/basename:

```bash
make download \
    MODEL=my-local-id \
    HF_REPO=owner/model-GGUF \
    HF_FILE=subdirectory/model-Q5_K_M.gguf
```

Private/gated repository access can use a token:

```bash
make download HF_REPO=owner/private-GGUF HF_QUANT=Q4_K_M HF_TOKEN=hf_...
```

The token is written only to a temporary mode-0600 curl configuration, removed
on exit, and unset from curl's environment. It is never recorded in model
metadata.

The downloader:

- queries repository metadata at download time rather than trusting fragile
  hard-coded file URLs;
- selects exact files, filename globs, or quantization tokens;
- detects and downloads every shard of split GGUF models;
- optionally resolves a matching multimodal projection with
  `DOWNLOAD_MMPROJ=1`;
- resumes `.part` transfers;
- uses per-model locks;
- checks disk and catalog RAM estimates;
- rejects HTML/error pages and Git LFS pointer text;
- validates the `GGUF` header;
- verifies exact published size and LFS SHA-256 when available;
- computes and records a local SHA-256 for every file;
- keeps invalid completed payloads as `.corrupt.<timestamp>.<pid>`;
- writes `model.path`, `files.tsv`, and `download.meta` only after validation.

`STRICT_CHECKSUM=1` rejects repositories that do not publish an LFS SHA-256.
`FORCE_DOWNLOAD=1` replaces a valid local copy only after a newly downloaded
payload passes validation. `OFFLINE=1` validates and reuses an existing complete
copy without contacting Hugging Face.

A finite menu can never enumerate all compatible GGUFs. The custom repository
path is therefore the authoritative escape hatch for new models and quants.
PyTorch, safetensors, legacy GGML, and Whisper checkpoints are intentionally
rejected rather than being mislabeled as GGUF.

## CLI and benchmarks

`make run` uses detected physical CPU cores for generation and logical cores for
batch/prompt work unless overridden:

```bash
make run \
    MODEL=qwen3.5-0.8b-q4_k_m \
    RUNTIME_THREADS=8 \
    RUNTIME_THREADS_BATCH=16 \
    GPU_LAYERS=auto \
    CTX_SIZE=8192 \
    PROMPT='Write a POSIX shell function that validates a path.'
```

Extra upstream arguments can be supplied through `ARGS`:

```bash
make run MODEL=qwen3-8b-q4_k_m ARGS='--temp 0.6 --top-p 0.9'
```

Benchmark the same staged build/model:

```bash
make bench MODEL=qwen3-8b-q4_k_m
make bench MODEL=qwen3-8b-q4_k_m ARGS='-p 512 -n 128'
```

Use `make list-devices` after a GPU build to inspect upstream device names, then
set `RUNTIME_DEVICE` or `SERVER_DEVICE` when explicit device selection is
needed.

## Foreground llama-server

The foreground server uses the same model resolver:

```bash
make server \
    SERVER_MODEL=qwen3.5-0.8b-q4_k_m \
    SERVER_HOST=127.0.0.1 \
    SERVER_PORT=8080
```

A basic health check and OpenAI-compatible request:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"local-model","messages":[{"role":"user","content":"Hello"}]}'
```

The wrapper refuses a non-loopback `SERVER_HOST` unless `SERVER_API_KEY` is set.
The key is exported as `LLAMA_API_KEY`, keeping it out of `ExecStart` and the
server command line. Network exposure still requires appropriate firewall,
TLS/reverse-proxy, authentication, and model prompt-safety decisions.

Embedding-only models require:

```dotenv
SERVER_EMBEDDINGS=1
SERVER_JINJA=0
```

Reranking models can use `SERVER_RERANKING=1`. Do not use embedding checkpoints
as chat models.

## Persistent rootless llama-server

Persistence is opt-in. The service runs as the current user and references the
staged binary/model in this repository; it does not install them system-wide.

Recommended `.env` baseline:

```dotenv
ENABLE_USER_SERVICE=1
SERVER_MODEL=qwen3.5-0.8b-q4_k_m
SERVER_HOST=127.0.0.1
SERVER_PORT=8080
SERVER_KEEP_MODEL_LOADED=1
SERVER_PIN_MODEL=0
SERVER_FULL_GPU_OFFLOAD=0
SERVER_GPU_LAYERS=auto
```

Render and inspect before enabling:

```bash
make service-render
cat output/systemd/llama-server-native.service
make service-enable ENABLE_USER_SERVICE=1
make service-status
make service-logs
```

Lifecycle:

```bash
make service-stop
make service-start
make service-restart
make service-disable
make service-uninstall
```

How residency settings map to `llama-server`:

| Setting | Effect |
|---|---|
| `SERVER_KEEP_MODEL_LOADED=1` | Passes `--sleep-idle-seconds -1`, disabling idle unload so weights and KV allocations remain resident while the service runs. |
| `SERVER_KEEP_MODEL_LOADED=0` | Uses `SERVER_SLEEP_IDLE_SECONDS`; after inactivity the server may unload model memory and reload on the next request. |
| `SERVER_PIN_MODEL=1` | Forces `--load-mode mmap+mlock`; the unit grants `LimitMEMLOCK=infinity`. Enough physical RAM is still required. |
| `SERVER_FULL_GPU_OFFLOAD=1` | Requests `--n-gpu-layers all`; this succeeds only with a compatible GPU build and sufficient VRAM. |
| `SERVER_GPU_LAYERS=auto` | Lets current llama.cpp fit/offload layers automatically. A number requests partial offload. |
| `SERVER_CACHE_TYPE_K/V` | Controls KV-cache precision and memory use; `f16` is conservative, quantized cache types trade memory for possible quality/performance effects. |
| `SERVER_PARALLEL` | Number of concurrent slots; more slots increase KV-cache and runtime memory. |

“Persistent” has two independent meanings:

1. the server process is supervised/restarted by the systemd user manager; and
2. idle model unloading is disabled with `SERVER_KEEP_MODEL_LOADED=1`.

A normal user service may stop after the final login session. To intentionally
run it without an active login, an administrator can enable user lingering:

```bash
sudo loginctl enable-linger "$USER"
```

This repository reports linger status but never changes it automatically.

The generated private configuration is stored at
`output/systemd/<service>.conf` with mode `0600`. The installed unit goes to
`${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/`. `make clean`, `distclean`, and
`purge` refuse to remove staged files while that unit remains installed; run
`make service-uninstall` first.

## Safety and reproducibility

Managed directories contain marker files. Cleanup and source-update operations
refuse unmarked non-empty paths, overlapping source/build/output layouts, unsafe
root/home paths, and external directories unless `ALLOW_EXTERNAL_DIRS=1` is
explicitly set. `purge` additionally requires `CONFIRM=YES`.

The source checkout refuses tracked modifications unless
`FORCE_SOURCE_RESET=1`. Build metadata records:

- upstream repository, configured ref, and exact commit;
- host/kernel and selected backend;
- compiler/CMake versions and effective Release flags;
- detected CUDA or AMD architecture targets;
- build target list;
- SHA-256 for each staged executable;
- `file(1)` and `ldd` output where available.

## Troubleshooting

**Illegal instruction on another computer** — expected for a host-native build.
Rebuild there or use `GGML_NATIVE=0`.

**CMake generator/compiler changed** — run `make clean`, then rebuild. The
wrapper refuses to reuse a cache from another source tree, generator, or
compiler.

**GPU build works but no layers offload** — run `make list-devices`, inspect
startup logs, verify the vendor driver/runtime, and review
`output/metadata/ldd.txt`. Try an explicit `SERVER_DEVICE` and
`SERVER_GPU_LAYERS`.

**Out of memory despite a model fitting on disk** — weight size excludes KV
cache, graph buffers, mmproj, parallel slots, and some backend scratch memory.
Reduce `CTX_SIZE`/`SERVER_CTX_SIZE`, `SERVER_PARALLEL`, GPU layers, or choose a
smaller/more aggressive quant.

**`mlock` fails** — foreground shells often have a low `ulimit -l`; the generated
systemd unit sets `LimitMEMLOCK=infinity`, but kernel/cgroup policy and actual
RAM still apply.

**CPU performance worsens with more threads** — generation often scales best to
physical cores and is memory-bandwidth limited. The defaults deliberately use
physical cores for generation. Benchmark instead of assuming SMT is faster.

**Download API or filename changed** — rerun against the repository's current
metadata, select an exact `HF_FILE`, or use a different compatible converter
repository. The model card/license remains authoritative.

## Tests

`make test` is offline and creates temporary local fixtures. It validates shell
syntax, manifest structure, GGUF selection/split handling, token isolation,
checksum policy, corruption recovery, source pinning, CMake compilation,
staging, executable verification, safe cleanup, server command construction,
and rootless service lifecycle behavior.

The integration CMake project is deliberately synthetic; it proves wrapper
orchestration without downloading upstream source or multi-gigabyte models.
A real `make build` remains the final validation for the selected compiler,
backend SDK, and current host.

## Licenses

This wrapper is MIT-licensed. `llama.cpp`, GPU SDKs, and every model retain their
own licenses and acceptable-use terms. Selecting or downloading a catalog entry
does not grant rights beyond its upstream license. The exact model card and
repository are authoritative. See `docs/SOURCES.md` and `models/README.md`.
