# FIMLoom.nvim

Local-first inline code completion for Neovim.

FIMLoom sends bounded code before and after the cursor to an Ollama or
llama.cpp endpoint, then previews the result as non-editing ghost text. It is
designed for local inference: no account, API key, cloud service, telemetry, or
automatic model download is required.

> [!IMPORTANT]
> FIMLoom is an early project. The `v0.1.0` API focuses on one job—fast,
> cancellable fill-in-the-middle completion—and intentionally excludes chat,
> agents, repository indexing, and cloud providers.

## Features

- Ollama and llama.cpp provider adapters with configurable endpoints and ports.
- Model selection in Neovim configuration.
- Debounced, asynchronous completion through `curl` and `vim.system()`.
- UTF-8-safe, byte-bounded prefix and suffix context.
- Single-line and multiline extmark previews that do not modify the buffer.
- Cancellation and stale-response rejection whenever editing state changes.
- Conflict-aware accept, dismiss, and manual-completion mappings.
- Optional argv-only server startup with readiness polling.
- Ownership-aware shutdown: FIMLoom stops only processes it started.
- `:FIMLoom` controls, `:checkhealth fimloom`, and privacy-filtered diagnostics.
- No runtime Lua dependencies.

## How it works

1. An Insert-mode change starts or resets a short debounce timer.
2. FIMLoom cancels older work and captures bounded text around the cursor.
3. The selected provider converts that context into a native FIM request.
4. `curl` performs the request asynchronously.
5. The response is ignored unless the buffer, window, changed tick, and cursor
   still match the original request.
6. Valid text appears through extmarks and is inserted only when accepted.

The initial release uses non-streaming requests. The editor remains responsive,
but the complete suggestion appears after the local model finishes generating.

## Requirements

- Neovim 0.10 or newer.
- `curl` available in `$PATH`.
- One local inference server:
  - [Ollama](https://ollama.com/), or
  - [`llama-server`](https://github.com/ggml-org/llama.cpp/tree/master/tools/server)
    from llama.cpp.
- A code model that supports fill-in-the-middle generation.
- Linux or macOS for managed-process guarantees in `v0.1.0`.

FIM-capable base/code-completion models generally produce better inline
suggestions than chat or instruction-only models. Model size, quantization,
context size, and hardware determine latency and quality.

## Installation

### lazy.nvim

```lua
{
  "AnkurAlpha/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "ollama",
    model = "qwen2.5-coder:1.5b-base",
  },
}
```

`opts` is passed to `require("fimloom").setup(opts)` by lazy.nvim. The `cmd`
trigger lets `:FIMLoom ...` load the plugin before the first Insert-mode entry.

### Local development checkout

```lua
{
  dir = "/home/ankur/git_work/github/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "ollama",
    model = "qwen2.5-coder:1.5b-base",
  },
}
```

When the plugin is lazy-loaded, run `:FIMLoom status` or enter Insert mode
before using `:checkhealth fimloom`.

## Ollama quick start

FIMLoom never downloads models automatically. Pull a FIM-capable model yourself:

```sh
ollama pull qwen2.5-coder:1.5b-base
```

Then configure FIMLoom to use an existing Ollama service:

```lua
{
  "AnkurAlpha/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "ollama",
    endpoint = "http://127.0.0.1:11434",
    model = "qwen2.5-coder:1.5b-base",
    server = {
      auto_start = false,
    },
  },
}
```

If Ollama is not already managed by your operating system or desktop app,
FIMLoom can start it:

```lua
opts = {
  provider = "ollama",
  endpoint = "http://127.0.0.1:11434",
  model = "qwen2.5-coder:1.5b-base",
  server = {
    auto_start = true,
    auto_stop = true,
    command = { "ollama", "serve" },
  },
}
```

FIMLoom probes `GET /api/tags` first. If the configured service is already
healthy, it is treated as external and will not be stopped. Otherwise, the
configured command is started and polled until ready.

The example model is deliberately small for responsiveness. Choose a larger
installed code model if your hardware can serve it with acceptable latency.

## llama.cpp quick start

Build or install `llama-server`, then obtain a FIM-capable GGUF model yourself.
FIMLoom does not download, convert, or select model files.

```lua
{
  "AnkurAlpha/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "llamacpp",
    endpoint = "http://127.0.0.1:8012",
    model = "/home/ankur/models/code-model.gguf",
    server = {
      auto_start = true,
      auto_stop = true,
      startup_timeout_ms = 60000,
      command = function(config)
        return {
          "llama-server",
          "--model",
          config.model,
          "--host",
          "127.0.0.1",
          "--port",
          "8012",
          "--ctx-size",
          "8192",
        }
      end,
    },
  },
}
```

The endpoint and `--port` must match. Add hardware-specific llama.cpp arguments,
such as GPU-layer settings, to the returned argv list when appropriate.

For a server started outside Neovim, omit `command` and keep
`server.auto_start = false`. The configured `model` path is then diagnostic
metadata; the external llama.cpp server decides which model is actually loaded.

## First completion

1. Start Neovim and make sure the plugin has loaded.
2. Run `:checkhealth fimloom`.
3. Open a normal, modifiable source-code buffer.
4. Enter Insert mode and type, or press `<M-\>` for a manual request.
5. Press `<Tab>` to accept visible ghost text or `<C-]>` to dismiss it.

Some terminals do not transmit `<M-\>` distinctly. Configure another manual
mapping if it does not reach Neovim.

## Configuration

The complete default configuration is shown below. `endpoint` is selected from
the provider when omitted: `http://127.0.0.1:11434` for Ollama and
`http://127.0.0.1:8012` for llama.cpp. `model` and `server.command` default to
`nil`.

```lua
require("fimloom").setup({
  enabled = true,
  provider = "ollama",
  endpoint = nil,
  model = nil,

  completion = {
    mode = "fim",
    auto_trigger = true,
    debounce_ms = 180,
    context = {
      max_prefix_bytes = 12000,
      max_suffix_bytes = 4000,
      filetypes = {
        allow = {},
        deny = {},
      },
    },
    generation = {
      max_tokens = 128,
      temperature = 0.2,
    },
    preview = {
      max_bytes = 16 * 1024,
      max_lines = 100,
    },
  },

  transport = {
    connect_timeout_ms = 1000,
    request_timeout_ms = 15000,
    max_response_bytes = 1024 * 1024,
  },

  server = {
    auto_start = false,
    auto_stop = true,
    command = nil,
    startup_timeout_ms = 30000,
    startup_poll_interval_ms = 250,
  },

  log = {
    level = "warn",
    max_entries = 200,
    file = false,
    max_file_bytes = 512 * 1024,
    notify = true,
    notify_cooldown_ms = 5000,
  },

  keymaps = {
    accept = "<Tab>",
    dismiss = "<C-]>",
    manual = "<M-\\>",
  },
})
```

### Configuration reference

| Option | Meaning |
| --- | --- |
| `enabled` | Start completion and lifecycle handling during setup. |
| `provider` | Built-in adapter: `"ollama"` or `"llamacpp"`. |
| `endpoint` | HTTP(S) base URL. Custom ports are preserved. Queries, fragments, whitespace, and embedded credentials are rejected. |
| `model` | Ollama model name, or llama.cpp model metadata/path used by a startup command. Ollama requires it before completion. |
| `completion.mode` | Only `"fim"` is supported in `v0.1.0`. |
| `completion.auto_trigger` | Schedule completion after Insert-mode text changes. |
| `completion.debounce_ms` | Delay after typing before a request starts; `0` disables the delay. |
| `completion.context.max_prefix_bytes` | Maximum UTF-8-safe bytes captured before the cursor. |
| `completion.context.max_suffix_bytes` | Maximum UTF-8-safe bytes captured after the cursor. |
| `completion.context.filetypes.allow` | If non-empty, only these exact Neovim filetypes are eligible. |
| `completion.context.filetypes.deny` | Exact Neovim filetypes to exclude. Deny wins over allow. |
| `completion.generation.max_tokens` | Provider generation limit (`num_predict` or `n_predict`). |
| `completion.generation.temperature` | Sampling temperature from `0` to `2`. |
| `completion.preview.max_bytes` | Maximum UTF-8-safe completion bytes displayed. |
| `completion.preview.max_lines` | Maximum completion lines displayed. |
| `transport.connect_timeout_ms` | `curl` connection timeout. |
| `transport.request_timeout_ms` | Whole-request timeout. |
| `transport.max_response_bytes` | Maximum accepted HTTP response size. |
| `server.auto_start` | Start `server.command` only when the initial health probe fails. Requires a command when true. |
| `server.auto_stop` | Stop an owned server on normal `VimLeavePre`; false starts the job detached. |
| `server.command` | Non-empty argv list, a function returning one, or `nil`. Shell strings are rejected. |
| `server.startup_timeout_ms` | Hard readiness deadline after an owned process starts. |
| `server.startup_poll_interval_ms` | Delay between asynchronous health probes while starting. |
| `log.level` | `"off"`, `"error"`, `"warn"`, `"info"`, or `"debug"`. |
| `log.max_entries` | Maximum privacy-filtered entries retained in memory. |
| `log.file` | `false`, `true` for Neovim's log directory, or a custom path. |
| `log.max_file_bytes` | Bound for the optional JSONL diagnostic file. |
| `log.notify` | Show automatic failure notifications. Manual command results still display. |
| `log.notify_cooldown_ms` | Per-failure-key cooldown for automatic notifications. |
| `keymaps.accept` | Insert-mode accept mapping, or `false`. |
| `keymaps.dismiss` | Insert-mode dismiss mapping, or `false`. |
| `keymaps.manual` | Insert-mode manual request mapping, or `false`. |

Configuration is deep-copied and validated during `setup()`. User-owned tables
are not mutated. A dynamic `server.command` receives a defensive copy of the
resolved configuration and is validated when invoked.

### Filetype filtering

```lua
completion = {
  context = {
    filetypes = {
      allow = { "lua", "go", "rust" },
      deny = { "gitcommit" },
    },
  },
}
```

FIMLoom also rejects unmodifiable, readonly, binary, unloaded, and special
`buftype` buffers.

### Disable default mappings

```lua
keymaps = {
  accept = false,
  dismiss = false,
  manual = false,
}
```

FIMLoom installs a default mapping only if that exact Insert-mode key is free.
It will not overwrite an existing snippet, completion, or user mapping. When a
FIMLoom accept/dismiss mapping has nothing to handle, the original key is passed
through. Automatic requests also pause while Neovim's popup menu is visible.

## Commands

FIMLoom registers one command with completion:

| Command | Action |
| --- | --- |
| `:FIMLoom complete` | Request a completion immediately. |
| `:FIMLoom accept` | Accept the visible suggestion. |
| `:FIMLoom dismiss` | Cancel pending work and clear the suggestion. |
| `:FIMLoom enable` | Enable completion and lifecycle handling after setup. |
| `:FIMLoom disable` | Disable completion, cancel work, and stop owned server work. |
| `:FIMLoom toggle` | Toggle enabled state. |
| `:FIMLoom start` | Probe readiness and start the configured server if needed. |
| `:FIMLoom stop` | Stop only server work owned by this Neovim instance. |
| `:FIMLoom status` | Show concise, privacy-safe runtime status. |

## Lua API

```lua
local fimloom = require("fimloom")

fimloom.setup(options)
fimloom.enable()
fimloom.disable()
fimloom.toggle()
fimloom.complete()
fimloom.accept()
fimloom.dismiss()
fimloom.start()
fimloom.stop()

local configured = fimloom.is_configured()
local enabled = fimloom.is_enabled()
local resolved = fimloom.get_config()
local status = fimloom.status()
```

Returned configuration and status values are defensive/privacy-safe data. The
public status reports server output byte counts, not captured output contents.

## Server ownership and shutdown

FIMLoom distinguishes a healthy pre-existing service from a process it starts:

| Situation | Ownership | Shutdown behavior |
| --- | --- | --- |
| Endpoint is healthy before startup | External/unowned | Never stopped by FIMLoom. |
| Endpoint is unhealthy and FIMLoom starts `server.command` | Owned | Stopped on normal exit when `auto_stop = true`. |
| `auto_stop = false` | Owned while Neovim runs; process is detached | Left running on exit. |
| Startup fails or readiness times out | Owned work is cancelled | Started job is stopped and failure is recorded. |

`:FIMLoom stop` never sends a stop signal to a pre-existing server. Disabling
or reconfiguring the plugin tears down work owned by the current instance.

Normal cleanup uses Neovim job control and `VimLeavePre`. Cleanup cannot be
guaranteed after `SIGKILL`, a Neovim crash, kernel failure, or power loss.
`v0.1.0` also has no shared lease between multiple Neovim processes. If several
editors should share one server, run it externally and set `auto_start = false`
(or at least `auto_stop = false`).

## Privacy and diagnostics

For built-in providers, completion requests contain bounded prefix/suffix text
and generation parameters. They are sent only to `endpoint`. A loopback URL
keeps that HTTP traffic on the machine; a non-loopback URL sends buffer context
to another host and produces a health warning.

FIMLoom provides:

- no telemetry, accounts, authentication, or cloud provider;
- no repository indexing or cross-file context in `v0.1.0`;
- no automatic model downloads;
- bounded requests and responses;
- redaction of source-bearing diagnostic fields such as `prefix`, `suffix`,
  `prompt`, `body`, `response`, and `text`;
- persistent logging disabled by default;
- bounded JSONL logging when explicitly enabled.

Enable a local diagnostic file temporarily:

```lua
log = {
  level = "debug",
  file = true,
}
```

Run `:FIMLoom status` to see safe state metadata and `:checkhealth fimloom` for
actionable checks. Persistent logs may still contain endpoint, provider, model,
process, and error metadata, so review them before sharing.

## Troubleshooting

Start with:

```vim
:FIMLoom status
:checkhealth fimloom
```

| Symptom | Check |
| --- | --- |
| `:FIMLoom` is unknown | With lazy.nvim, enter Insert mode or run `:Lazy load fimloom.nvim`; include `cmd = "FIMLoom"` in the spec. |
| `curl` health error | Install `curl` and confirm it is in the environment used to start Neovim. |
| Endpoint is unreachable | Confirm the host/port, start the server, and test its native health endpoint. |
| Ollama model missing | Run `ollama list`, then explicitly `ollama pull <model>` and match `opts.model`. |
| llama.cpp returns 404 | Use `llama-server`'s native base URL and ensure its `/health` and `/infill` endpoints are enabled. |
| Startup executable missing | Correct the first item in `server.command` or install the executable. |
| Startup times out | Increase `server.startup_timeout_ms` and inspect server diagnostics outside FIMLoom. |
| No automatic suggestion | Confirm `auto_trigger`, buffer suitability, filetype filters, Insert mode, and that the popup menu is closed. |
| Manual key does nothing | Your terminal may not encode `<M-\>`; choose another `keymaps.manual`. |
| `<Tab>` does not accept | Another Insert-mode mapping already owns Tab; configure a free accept key or integrate explicitly. |
| Suggestion disappears | Typing, moving the cursor, changing buffers, or leaving Insert mode intentionally invalidates stale work. |
| Remote endpoint warning | Use `127.0.0.1`, `localhost`, or `[::1]` if context must remain on the local machine. |

Native probes useful outside Neovim:

```sh
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:8012/health
```

## Development

Requirements: Neovim 0.10+, `curl`, and
[StyLua](https://github.com/JohnnyMorganz/StyLua).

```sh
stylua lua plugin tests
stylua --check lua plugin tests
git diff --check
nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua
```

Validate the native help file:

```sh
nvim --headless --clean -u tests/minimal_init.lua \
  -c "helptags doc" \
  -c "silent help fimloom" \
  -c "quitall"
rm -f doc/tags
```

The automated suite uses a loopback fixture and does not download or run an
LLM. Before a release, manually test both providers, existing and managed server
ownership, cancellation after typing, buffer switching, multiline acceptance,
and normal-exit cleanup.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution rules and
[CHANGELOG.md](CHANGELOG.md) for release notes.

## Current limitations

- Non-streaming suggestions only.
- Current-buffer context only.
- One suggestion at a time.
- No chat, agent, refactoring, or repository-editing workflow.
- No `nvim-cmp` or `blink.cmp` integration.
- No Windows process-lifecycle guarantee.
- No crash-proof or multi-Neovim ownership lease.

The planned follow-ups include streaming, explicit chat-model fallback,
nearby-buffer/repository context, partial acceptance, completion-framework
integrations, per-filetype models, and stronger shared-server coordination.

## Acknowledgements

- [codeium.el](https://github.com/Exafunction/codeium.el) for completion-client
  architecture ideas.
- [Neovim](https://neovim.io/doc/) and
  [lazy.nvim](https://lazy.folke.io/spec) documentation.
- [Ollama](https://docs.ollama.com/api/generate) and
  [llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
  for local inference APIs.

FIMLoom is an original implementation. “Copilot” is used only as a familiar
feature comparison and is not part of the project name or identity.

## License

[MIT](LICENSE) © Ankur Kumar.
