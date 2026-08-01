# Changelog

All notable changes to FIMLoom.nvim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-08-01

### Added

- Matching-prefix consumption for visible inline suggestions, including
  character-by-character typing, multi-character insertion, newlines, and
  indentation, with strict editor-state validation and no duplicate acceptance.
- `completion.preserve_matching_prefix`, enabled by default.
- Configurable `FIMLoomSuggestion` colors through `ui.suggestion`, optional
  highlight linking through `ui.suggestion_hl`, and colorscheme-safe restoration.

### Fixed

- Restore configured suggestion highlight links after a colorscheme explicitly
  clears `FIMLoomSuggestion`, while continuing to preserve user and colorscheme
  definitions.
- Remove trailing whitespace-only output lines before both rendering and
  acceptance through the default-enabled `completion.trim_trailing_blank_lines`.
- Preserve internal blank lines and indentation while sanitizing multiline
  completions.
- Avoid replacement inference while a matching suggestion prefix is being
  consumed; restart normal debounced inference after divergence.

## [0.1.1] - 2026-07-19

### Added

- Document a multi-Neovim llama.cpp configuration that combines detached
  server ownership with `--sleep-idle-seconds` to release idle model weights.

### Fixed

- Claim the default Insert-mode `<Tab>` accept key using Codeium-style mapping
  precedence and schedule the buffer edit outside expression-mapping textlock.
  A literal Tab is passed through when no ghost-text suggestion is visible.

## [0.1.0] - 2026-07-19

### Added

- Local-first, non-streaming fill-in-the-middle completion for Neovim 0.10+.
- Native Ollama `/api/generate` and llama.cpp `/infill` adapters.
- Non-thinking Ollama FIM requests so reasoning content cannot become ghost
  text.
- A reusable JetBrains Mellum 4B Ollama Modelfile and llama.cpp example with
  the model's required suffix-prefix-middle ordering.
- Provider-specific health checks, custom endpoints/ports, and model selection.
- Asynchronous, cancellable `curl` transport with timeouts, byte bounds,
  structured failures, JSON validation, and loopback integration tests.
- UTF-8-safe bounded current-buffer context with filetype and buffer-suitability
  filtering.
- Debounced automatic requests, manual requests, monotonically increasing
  request IDs, and stale-response rejection.
- Single-line and multiline extmark ghost text with undo-friendly one-edit
  acceptance.
- Exact and conservative whitespace-tolerant suffix-overlap removal.
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

[Unreleased]: https://github.com/AnkurAlpha/fimloom.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/AnkurAlpha/fimloom.nvim/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/AnkurAlpha/fimloom.nvim/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AnkurAlpha/fimloom.nvim/releases/tag/v0.1.0
