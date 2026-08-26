# GGUF model catalog

`models.tsv` is the source of truth for `make models` and the interactive
`make download` menu. It is intentionally a curated desktop-oriented list,
not a claim to enumerate the thousands of GGUF repositories on Hugging Face.
Use `HF_REPO`, `HF_QUANT`, and `HF_FILE` for any other llama.cpp-compatible
GGUF.

The 17 tab-separated fields are:

1. local model ID;
2. task;
3. family;
4. approximate total parameters in billions;
5. approximate active parameters in billions (important for MoE models);
6. quantization;
7. approximate weight size in MiB;
8. estimated minimum host RAM in GiB;
9. estimated comfortable host RAM in GiB;
10. estimated VRAM for full weight offload in GiB;
11. recommended physical CPU-core range;
12. advertised context in thousands of tokens;
13. upstream license label;
14. Hugging Face repository;
15. model filename glob;
16. optional multimodal projection glob;
17. notes.

Resource columns are engineering estimates for model selection, not upstream
requirements or capacity guarantees. Runtime memory also depends on context,
KV-cache type, parallel slots, batch size, multimodal projection files, graph
buffers, backend scratch space, and operating-system workload. Full-offload
VRAM estimates include modest headroom but should not replace actual testing.

Catalog repositories may add, rename, split, or remove files. The downloader
queries current repository metadata, resolves all shards, and records the exact
remote paths and hashes used. Model licenses and cards can change; review them
before use or redistribution.

Whisper/Distil-Whisper checkpoints do not appear here because they are audio
models for whisper.cpp, not language-model GGUFs for llama.cpp.
