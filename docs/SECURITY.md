# Security notes

- The build and download paths are unprivileged and do not install into system
  directories.
- Managed-directory markers and overlap checks protect cleanup operations from
  deleting arbitrary paths.
- Hugging Face tokens are restricted to ordinary token characters, placed in a
  temporary mode-0600 curl configuration, removed on exit, and unset from the
  transport process environment.
- Downloaded files are rejected unless they have GGUF magic bytes. Published
  LFS size/SHA-256 metadata is verified when available; `STRICT_CHECKSUM=1`
  requires a published digest.
- The server refuses non-loopback binding without an API key. An API key is not
  a substitute for TLS, firewall policy, a reverse proxy, rate limiting, or
  prompt/data governance.
- The generated service configuration can contain `SERVER_API_KEY` and is mode
  0600. Do not commit `.env` or `output/systemd/*.conf`.
- `SERVER_EXTRA_ARGS` and `ARGS` are split on shell whitespace without `eval`.
  They do not support complex shell quoting; use direct binary invocation for
  arguments containing embedded whitespace.
- Enabling RPC, MCP, built-in tools, remote media access, or experimental server
  features changes the threat model. This wrapper does not enable them by
  default.
