# FIMLoom.nvim

Local-first inline code completion for Neovim.

FIMLoom sends bounded code before and after the cursor to an Ollama or
llama.cpp endpoint, then previews the result as non-editing ghost text. It is
designed for local inference: no account, API key, cloud service, telemetry, or
automatic model download is required.

> [!IMPORTANT]
> FIMLoom is an early project. The `v0.1.x` API focuses on one job—fast,
> cancellable fill-in-the-middle completion—and intentionally excludes chat,
> agents, repository indexing, and cloud providers.

## Features

- Ollama and llama.cpp provider adapters with configurable endpoints and ports.
- Model selection in Neovim configuration.
- Debounced, asynchronous completion through `curl` and `vim.system()`.
- UTF-8-safe, byte-bounded prefix and suffix context.
- Single-line and multiline extmark previews that do not modify the buffer.
- Matching typed prefixes progressively consume ghost text instead of discarding it.
- Trailing blank-line cleanup and a dedicated configurable grey suggestion highlight.
- Cancellation and stale-response rejection whenever editing state changes.
- Codeium-style `<Tab>` acceptance with conflict-aware dismiss and manual mappings.
- Optional argv-only server startup with readiness polling.
- Ownership-aware shutdown: FIMLoom stops only processes it started.
- `:FIMLoom` controls, `:checkhealth fimloom`, and privacy-filtered diagnostics.
- No runtime Lua dependencies.

## How it works

1. An Insert-mode change first consumes a matching visible suggestion prefix;
   otherwise it starts or resets a short debounce timer.
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
    model = "mellum:4b-fimloom",
  },
}
```

`opts` is passed to `require("fimloom").setup(opts)` by lazy.nvim. The `cmd`
trigger lets `:FIMLoom ...` load the plugin before the first Insert-mode entry.

### Local development checkout

```lua
{
  dir = "/absolute/path/to/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "ollama",
    model = "mellum:4b-fimloom",
  },
}
```

When the plugin is lazy-loaded, run `:FIMLoom status` or enter Insert mode
before using `:checkhealth fimloom`.

## Ollama quick start

FIMLoom never downloads models automatically. The examples below use
[JetBrains Mellum 4B base](https://huggingface.co/JetBrains/Mellum-4b-base), a
small model trained specifically for code completion and evaluated on
fill-in-the-middle benchmarks. Download the official Q8 GGUF once:

```sh
model_dir="$HOME/.local/share/fimloom/models"
model="$model_dir/mellum-4b-base.Q8_0.gguf"

mkdir -p "$model_dir"
curl --fail --location --continue-at - \
  --output "$model.part" \
  https://huggingface.co/JetBrains/Mellum-4b-base-gguf/resolve/main/mellum-4b-base.Q8_0.gguf

echo "f8a8ae8f8b02cd992716e8849fe0424184bc7a26c2b829131ed558567307c5b2  $model.part" \
  | sha256sum --check \
  && mv "$model.part" "$model"
```

The file is about 4.27 GB. Its published SHA-256 is checked before the partial
download is promoted. To import that local GGUF into Ollama, substitute its
absolute path into the Modelfile template shipped with FIMLoom:

```sh
model="$(realpath "$HOME/.local/share/fimloom/models/mellum-4b-base.Q8_0.gguf")"
sed "s|@MODEL_PATH@|$model|" \
  /path/to/fimloom.nvim/examples/mellum-4b-fim.Modelfile \
  > /tmp/FIMLoom.Mellum.Modelfile

ollama create mellum:4b-fimloom -f /tmp/FIMLoom.Mellum.Modelfile
rm -f /tmp/FIMLoom.Mellum.Modelfile
```

Replace `/path/to/fimloom.nvim` with the plugin checkout. The model name
`mellum:4b-fimloom` is local and can be changed as long as `opts.model` matches.
Ollama stores an imported model layer in its own model store; the original GGUF
can also be used directly by llama.cpp.

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
    model = "mellum:4b-fimloom",
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
  model = "mellum:4b-fimloom",
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

Ollama completion requests set `think = false` so reasoning text cannot become
inline code. The model must still expose fill-in-the-middle support through an
Ollama template containing `{{ .Suffix }}`.

Adding FIM tokens or a suffix-aware template does not train a general model to
perform infilling. Choose a base model whose documentation explicitly reports
FIM training or benchmarks. The Mellum manifest only exposes the FIM behavior
already present in its weights.

## llama.cpp quick start

Build or install `llama-server`, then obtain a FIM-capable GGUF model yourself.
The configuration below reuses the Mellum file from the Ollama quick start:

```lua
{
  "AnkurAlpha/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "llamacpp",
    endpoint = "http://127.0.0.1:8012",
    model = vim.fn.expand(
      "~/.local/share/fimloom/models/mellum-4b-base.Q8_0.gguf"
    ),
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
          "--n-gpu-layers",
          "999",
          "--spm-infill",
          "--no-warmup",
        }
      end,
    },
  },
}
```

The endpoint and `--port` must match. Mellum requires `--spm-infill` because it
uses suffix-prefix-middle token order. Other models may use the default
prefix-suffix-middle order, so do not copy that flag without checking their
model cards. Adjust GPU-layer and context arguments for the available hardware.

### Multiple Neovim sessions and idle GPU release

FIMLoom `v0.1.x` does not coordinate ownership between separate Neovim
processes. With `auto_stop = true`, the instance that started llama.cpp stops
it when that editor exits, even when another editor is still using it. For a
shared llama.cpp server, detach the process and let llama.cpp unload idle model
weights:

```sh
llama-server --help 2>&1 | rg -- "--sleep-idle-seconds"
```

When that option is available, change the server portion of the configuration
above as follows:

```lua
server = {
  auto_start = true,
  auto_stop = false,
  startup_timeout_ms = 60000,
  command = function(config)
    return {
      "llama-server",
      "--model", config.model,
      "--host", "127.0.0.1",
      "--port", "8012",
      "--ctx-size", "8192",
      "--n-gpu-layers", "999",
      "--spm-infill",
      "--no-warmup",
      "--sleep-idle-seconds", "300",
    }
  end,
}
```

Closing one Neovim instance will then leave the shared server available. After
five minutes without inference, llama.cpp unloads the model weights while the
server process remains alive. The next completion reloads the model and is
therefore slower. Some backends may retain a small GPU allocation while the
server sleeps; terminate the server to release everything. While its owning
editor is open, use `:FIMLoom stop`; after that editor exits, terminate the
specific `llama-server` process externally when needed.

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
    trim_trailing_blank_lines = true,
    preserve_matching_prefix = true,
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

  ui = {
    suggestion = {
      fg = "#808080",
      ctermfg = 244,
      italic = false,
    },
    suggestion_hl = nil,
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
| `completion.trim_trailing_blank_lines` | Remove every trailing whitespace-only output line before rendering and acceptance. Enabled by default. |
| `completion.preserve_matching_prefix` | Consume exact inserted prefixes from visible ghost text instead of requesting again. Enabled by default. |
| `completion.context.max_prefix_bytes` | Maximum UTF-8-safe bytes captured before the cursor. |
| `completion.context.max_suffix_bytes` | Maximum UTF-8-safe bytes captured after the cursor. |
| `completion.context.filetypes.allow` | If non-empty, only these exact Neovim filetypes are eligible. |
| `completion.context.filetypes.deny` | Exact Neovim filetypes to exclude. Deny wins over allow. |
| `completion.generation.max_tokens` | Provider generation limit (`num_predict` or `n_predict`). |
| `completion.generation.temperature` | Sampling temperature from `0` to `2`. |
| `completion.preview.max_bytes` | Maximum UTF-8-safe completion bytes displayed. |
| `completion.preview.max_lines` | Maximum completion lines displayed. |
| `ui.suggestion.fg` | GUI foreground for the dedicated `FIMLoomSuggestion` group when no group already exists. |
| `ui.suggestion.ctermfg` | Terminal-color fallback for `FIMLoomSuggestion`. |
| `ui.suggestion.italic` | Whether the plugin-provided suggestion highlight is italic. |
| `ui.suggestion_hl` | Optional highlight group to link `FIMLoomSuggestion` to; when set, this takes precedence over `ui.suggestion`. |
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

### Suggestion cleanup and matching-prefix typing

With `trim_trailing_blank_lines = true`, FIMLoom normalizes line endings and
removes all trailing lines containing only spaces or tabs, including the empty
line represented by a final newline. It does not trim the final content line or
alter blank lines inside the completion, so code indentation, strings,
comments, and Markdown layout remain intact. The sanitized text is stored once,
and the renderer and accept action use that same value.

With `preserve_matching_prefix = true`, an insertion is consumed only when it
is a byte-exact prefix of the visible suggestion and the buffer change is a
single verified insertion at the suggestion anchor. Single characters,
multi-character paste, UTF-8 text, newlines, and indentation are supported.
Backspace, cursor movement, undo, buffer changes, popup-menu edits, or any
mismatch clear the old suggestion; normal debounced completion then resumes
when appropriate. Typing the whole suggestion clears it without inserting a
duplicate.

### Suggestion highlight

Ghost text always renders with `FIMLoomSuggestion`. By default the group uses a
neutral `#808080` foreground, terminal color `244`, no background, and no
italic styling. To choose another grey in configuration:

```lua
ui = {
  suggestion = {
    fg = "#707070",
    ctermfg = 242,
    italic = true,
  },
}
```

To follow an existing colorscheme group instead:

```lua
ui = {
  suggestion_hl = "Comment",
}
```

Precedence is: an already defined manual `FIMLoomSuggestion` group wins;
otherwise `ui.suggestion_hl` wins over `ui.suggestion`; otherwise the neutral
default is used. FIMLoom checks whether the group is empty before applying its
definition, so it does not replace an explicit user or colorscheme definition.
A `ColorScheme` autocmd restores the configured/default definition only if the
group was cleared. A manual override can therefore be placed before or after
setup:

```lua
vim.api.nvim_set_hl(0, "FIMLoomSuggestion", {
  fg = "#707070",
  italic = true,
})
```

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

Like Codeium, FIMLoom installs its configured accept mapping unconditionally.
The default `<Tab>` therefore takes ownership while FIMLoom is enabled, accepts
visible ghost text first, and otherwise passes through a literal Tab. This
intentionally replaces any earlier mapping on that key. Set
`keymaps.accept = false` and integrate `require("fimloom").accept()` into your
own mapping if you need snippet or completion-framework priority. Dismiss and
manual mappings remain conflict-aware and are installed only when their exact
keys are free. Automatic requests also pause while Neovim's popup menu is
visible.

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
`v0.1.x` also has no shared lease between multiple Neovim processes. If several
editors should share one server, run it externally and set `auto_start = false`,
or use the detached llama.cpp idle-sleep recipe documented above.

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
| Ollama says the model does not support insert | Use a genuine FIM model and a suffix-aware manifest; see the Mellum Ollama quick start. |
| llama.cpp returns 404 | Use `llama-server`'s native base URL and ensure its `/health` and `/infill` endpoints are enabled. |
| Mellum produces poor llama.cpp infills | Start `llama-server` with `--spm-infill`; Mellum uses suffix-prefix-middle order. |
| Startup executable missing | Correct the first item in `server.command` or install the executable. |
| Startup times out | Increase `server.startup_timeout_ms` and inspect server diagnostics outside FIMLoom. |
| No automatic suggestion | Confirm `auto_trigger`, buffer suitability, filetype filters, Insert mode, and that the popup menu is closed. |
| Manual key does nothing | Your terminal may not encode `<M-\>`; choose another `keymaps.manual`. |
| `<Tab>` does not accept | Run `:verbose imap <Tab>` and confirm it says `FIMLoom: accept inline suggestion`. If another plugin owns it, make FIMLoom load later or configure another accept key. |
| Suggestion disappears while typing | Exact prefix typing is preserved by default. A mismatch, backspace, cursor move, popup-menu edit, undo, external edit, buffer change, or Insert-mode exit intentionally invalidates it. |
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
