# Primary design sources

Reviewed on 2026-08-05. The default upstream source ref is llama.cpp `b10270`.
The project records the exact fetched commit because llama.cpp evolves rapidly.

## llama.cpp

- Repository and quick start: https://github.com/ggml-org/llama.cpp
- Releases: https://github.com/ggml-org/llama.cpp/releases
- Build guide: https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md
- Top-level CMake interface: https://github.com/ggml-org/llama.cpp/blob/master/CMakeLists.txt
- GGML CMake interface: https://github.com/ggml-org/llama.cpp/blob/master/ggml/CMakeLists.txt
- Server documentation and argument reference: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- Multi-GPU documentation: https://github.com/ggml-org/llama.cpp/blob/master/docs/multi-gpu.md
- OpenVINO backend: https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENVINO.md
- SYCL backend: https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/SYCL.md
- OpenCL backend: https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENCL.md

The current server documentation defines `--n-gpu-layers auto|all|N`,
`--load-mode none|mmap|mlock|mmap+mlock|dio`, `--sleep-idle-seconds`,
quantized KV-cache types, embedding/reranking modes, and `LLAMA_API_KEY`.
Those interfaces are mapped directly by `scripts/server-launch.sh`.

## Hugging Face model metadata

The downloader uses the public model-information API and LFS metadata at run
time rather than embedding immutable direct URLs:

- API documentation: https://huggingface.co/docs/hub/api
- Hub download documentation: https://huggingface.co/docs/huggingface_hub/guides/download
- ggml-org models: https://huggingface.co/ggml-org

Representative catalog repositories include Qwen, Llama, Gemma, Phi, Mistral,
DeepSeek distillations, Granite, SmolLM, GPT-OSS, and embedding checkpoints.
Each row in `models/models.tsv` contains its actual repository identifier and a
license label, but the live model card remains authoritative.

The RAM, VRAM, and CPU recommendations are local engineering estimates for
personal computers. Parameter counts and advertised context sizes are rounded
where model cards use rounded figures.
