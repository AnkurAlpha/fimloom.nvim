# Changelog

All notable changes to FIMLoom.nvim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-18

### Added

- Local-first, non-streaming fill-in-the-middle completion for Neovim 0.10+.
- Native Ollama `/api/generate` and llama.cpp `/infill` adapters.
- Provider-specific health checks, custom endpoints/ports, and model selection.
- Asynchronous, cancellable `curl` transport with timeouts, byte bounds,
  structured failures, JSON validation, and loopback integration tests.
- UTF-8-safe bounded current-buffer context with filetype and buffer-suitability
  filtering.
- Debounced automatic requests, manual requests, monotonically increasing
  request IDs, and stale-response rejection.
- Single-line and multiline extmark ghost text with undo-friendly one-edit
  acceptance.
- Conflict-aware Insert-mode mappings for accept, dismiss, and manual requests.
- Optional argv-only server startup, readiness polling, bounded process output,
  ownership tracking, and normal-exit cleanup.
- `:FIMLoom` subcommands for completion, lifecycle, state, and suggestions.
- `:checkhealth fimloom` checks for dependencies, configuration, endpoint
  locality, provider readiness, ownership, startup executable, and model
  availability.
- Bounded, redacted in-memory diagnostics, optional JSONL persistence, and
  rate-limited automatic notifications.
- Headless automated tests, StyLua configuration, GitHub Actions CI, native
  Vim help, contribution guidance, implementation plan, and MIT license.

### Security and privacy

- Source-bearing diagnostic fields are redacted by default.
- Persistent logging is opt-in and bounded.
- Startup commands are argument arrays and never shell strings.
- FIMLoom stops only local inference jobs it started.
- Endpoint URLs reject embedded credentials, query strings, and fragments.
- Non-loopback endpoints produce a health warning because buffer context leaves
  the local machine.

### Known limitations

- No streaming, chat/agent mode, cross-file context, alternative suggestions,
  or completion-framework integration.
- Managed-process guarantees target Linux and macOS; Windows is not guaranteed.
- Normal-exit cleanup cannot cover crashes, `SIGKILL`, kernel failure, or power
  loss.
- Ownership is not coordinated across multiple Neovim processes.

[Unreleased]: https://github.com/AnkurAlpha/fimloom.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AnkurAlpha/fimloom.nvim/releases/tag/v0.1.0
