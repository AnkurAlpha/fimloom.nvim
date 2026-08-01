# FIMLoom.nvim Implementation Plan

> Local-first inline code completion for Neovim.

- **Document status:** Implemented through Stage 8; Stage 9 publication pending
- **Target release:** `v0.1.0`
- **Primary language:** Lua
- **License:** MIT
- **Initial platform:** Neovim 0.10+ on Linux and macOS

## 1. Purpose

FIMLoom.nvim will provide Copilot-style inline code suggestions in Neovim using
models served locally by Ollama or llama.cpp. It will collect a bounded amount
of code around the cursor, request a completion asynchronously, display the
result as ghost text, and allow the user to accept or dismiss the suggestion.

The model, endpoint, and optional server startup command will be configured in
the user's Neovim configuration. If FIMLoom starts a server itself, it will
track ownership and terminate that server during a normal Neovim exit.

The project is local-first:

- no cloud provider is required;
- no account, API key, telemetry, or authentication flow is required;
- source code is sent only to the endpoint explicitly configured by the user;
- model downloads and model selection remain under the user's control.

## 2. Brand and Naming

- Public name: **FIMLoom.nvim**
- Repository name: `fimloom.nvim`
- Lua module: `fimloom`
- Command prefix: `FIMLoom`
- Tagline: **Local-first inline code completion for Neovim.**

“FIM” refers to fill-in-the-middle generation: a model receives the code before
and after the cursor and predicts the missing portion. “Loom” represents
weaving the generated code into the current buffer.

The name does not mean that instruction/chat models are forbidden. FIM-capable
code models will use the native completion path, while a slower chat fallback
can be added behind an explicit configuration mode.

## 3. Product Principles

1. **Local-first and transparent**
   The configured endpoint and the context sent to it must be understandable
   and inspectable.

2. **Never block editing**
   Server health checks, HTTP requests, startup polling, and completion work
   must be asynchronous.

3. **Latest request wins**
   An old response must never appear after the buffer or cursor has changed.

4. **Own only what we start**
   FIMLoom must not terminate an Ollama or llama.cpp server that was already
   running when the plugin loaded.

5. **Safe command execution**
   Startup commands will use argument arrays. The plugin will not interpolate
   model paths or user options into shell command strings.

6. **Small runtime surface**
   The MVP will be implemented in Lua and Neovim APIs. `curl` will be the only
   external runtime utility because it provides reliable cancellable HTTP
   without requiring LuaRocks or a large Neovim dependency.

7. **Provider-specific behavior behind one interface**
   Ollama and llama.cpp request and response formats will remain isolated in
   provider modules.

## 4. MVP Scope (`v0.1.0`)

### Included

- Configuration through `require("fimloom").setup(...)`.
- Installation and local-development examples for `lazy.nvim`.
- User-selectable provider, endpoint, and model.
- Ollama native `/api/generate` FIM requests.
- llama.cpp native `/infill` requests.
- Non-streaming requests for the first stable implementation.
- Asynchronous HTTP using `vim.system()` and `curl`.
- Debounced automatic completion while typing in Insert mode.
- Manual completion command/keymap.
- Cancellation of obsolete HTTP requests.
- Stale-response protection using a monotonically increasing request ID,
  buffer identity, buffer `changedtick`, and cursor position.
- Single-line and multiline ghost-text rendering with Neovim extmarks.
- Configurable accept, dismiss, manual-trigger, enable, and disable keymaps.
- Optional server startup with an argument-vector command.
- Health polling after a server is started.
- Graceful shutdown of a server owned by the current Neovim instance.
- User commands for enable, disable, toggle, complete, start, stop, and status.
- `:checkhealth fimloom` integration.
- Debug logging with source-code content excluded by default.
- Unit tests for pure modules and headless integration smoke tests.
- README, help file, MIT license, changelog, contributing guide, and CI.

### Explicitly not included in `v0.1.0`

- Chat sidebar, agent mode, refactoring workflow, or repository editing.
- Cloud providers or API-key management.
- Automatic model downloads or `ollama pull`.
- Repository-wide indexing, embeddings, or vector databases.
- Cross-file context discovery. The provider interface will leave room for it.
- `nvim-cmp` or `blink.cmp` integration.
- Windows process-lifecycle guarantees.
- Multiple simultaneous alternative suggestions.
- Token-by-token streaming UI. This is planned after the non-streaming path is
  stable and fully cancellable.
- Guaranteed cleanup after `SIGKILL`, kernel failure, power loss, or a Neovim
  crash. Normal exits will be handled with `VimLeavePre`.
- Coordinated ownership across multiple Neovim processes. Users who routinely
  share one server between several Neovim instances should set
  `server.auto_stop = false` in the initial release.

## 5. Compatibility and Requirements

### Required

- Neovim 0.10 or later.
- `curl` available in `$PATH`.
- One of:
  - Ollama with its HTTP API enabled; or
  - `llama-server` from llama.cpp.
- A model compatible with the selected completion mode.

### Recommended

- A code model trained for fill-in-the-middle generation.
- A loopback endpoint such as `http://127.0.0.1:11434` or
  `http://127.0.0.1:8012`.
- Low-temperature generation and a modest token limit for responsive inline
  suggestions.

Instruction/chat models can generate code, but they may be slower and less
reliable for true cursor infilling. FIMLoom will document this rather than claim
that every model produces equal-quality completions.

## 6. User Experience

### Normal completion flow

1. The user enters Insert mode and types.
2. A `TextChangedI`/`TextChangedP` event first attempts verified matching-prefix
   consumption, then schedules a debounced completion only when needed.
3. Any previous timer and obsolete request are cancelled.
4. FIMLoom captures bounded prefix and suffix context.
5. The selected provider builds its request payload.
6. The request runs asynchronously.
7. Before rendering, FIMLoom verifies that the request is still current.
8. The completion is cleaned and displayed as ghost text.
9. The user accepts it, dismisses it, or keeps typing.

### Expected controls

The exact defaults will be finalized during implementation, with every mapping
configurable. The proposed defaults are:

| Action | Proposed default | Behavior |
| --- | --- | --- |
| Accept suggestion | `<Tab>` | Accept when visible; otherwise preserve normal Tab behavior |
| Dismiss suggestion | `<C-]>` | Clear the current suggestion |
| Request manually | `<M-\>` | Request a completion immediately |
| Toggle plugin | command only | `:FIMLoom toggle` |

The `<Tab>` mapping uses Codeium-style precedence: it accepts visible ghost
text and otherwise emits a literal Tab. It deliberately replaces an earlier
mapping on that key. Users who need snippet or completion-framework priority
can disable the default accept mapping and integrate the public accept API.
Automatic completion pauses while an existing completion popup is visible.

### Commands

```text
:FIMLoom enable
:FIMLoom disable
:FIMLoom toggle
:FIMLoom complete
:FIMLoom accept
:FIMLoom dismiss
:FIMLoom start
:FIMLoom stop
:FIMLoom status
```

The subcommand form avoids filling the command namespace with many independent
commands. Command completion will list valid subcommands.

## 7. Proposed Configuration

The public configuration must remain data-oriented so `lazy.nvim` can pass it
through `opts` directly.

### Ollama example

```lua
{
  "AnkurAlpha/fimloom.nvim",
  event = "InsertEnter",
  opts = {
    provider = "ollama",
    endpoint = "http://127.0.0.1:11434",
    model = "mellum:4b-fimloom",

    completion = {
      mode = "fim",
      auto_trigger = true,
      debounce_ms = 180,
      trim_trailing_blank_lines = true,
      preserve_matching_prefix = true,
      context = {
        max_prefix_bytes = 12000,
        max_suffix_bytes = 4000,
      },
      generation = {
        max_tokens = 128,
        temperature = 0.2,
      },
    },

    server = {
      auto_start = true,
      auto_stop = true,
      command = { "ollama", "serve" },
      startup_timeout_ms = 30000,
    },
  },
}
```

The public repository path is `AnkurAlpha/fimloom.nvim`.

### llama.cpp example

```lua
{
  dir = "/absolute/path/to/fimloom.nvim",
  event = "InsertEnter",
  opts = {
    provider = "llamacpp",
    endpoint = "http://127.0.0.1:8012",
    model = vim.fn.expand(
      "~/.local/share/fimloom/models/mellum-4b-base.Q8_0.gguf"
    ),

    completion = {
      mode = "fim",
      debounce_ms = 180,
      generation = {
        max_tokens = 128,
        temperature = 0.2,
      },
    },

    server = {
      auto_start = true,
      auto_stop = true,
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
        }
      end,
      startup_timeout_ms = 60000,
    },
  },
}
```

Both a fixed argument array and a function returning an argument array will be
supported. A shell string will not be accepted in the MVP because it makes
escaping, ownership, and child-process cleanup less reliable.

### Configuration validation

`setup()` will validate values early and report actionable errors:

- provider must exist in the provider registry;
- endpoint must be an HTTP or HTTPS URL;
- model must be a non-empty string where required;
- command must be an argv-style list or a function returning one;
- debounce, timeouts, byte limits, and token limits must be non-negative
  numbers in safe ranges;
- keymaps can be disabled with `false`;
- unknown top-level configuration keys will produce a warning in debug mode.

Defaults will be deep-copied for every setup so user tables are never mutated.

## 8. Technical Architecture

### Module layout

```text
fimloom.nvim/
├── plugin/
│   └── fimloom.lua
├── lua/
│   └── fimloom/
│       ├── init.lua
│       ├── config.lua
│       ├── state.lua
│       ├── commands.lua
│       ├── completion.lua
│       ├── context.lua
│       ├── output.lua
│       ├── render.lua
│       ├── transport.lua
│       ├── process.lua
│       ├── log.lua
│       ├── health.lua
│       └── providers/
│           ├── init.lua
│           ├── ollama.lua
│           └── llamacpp.lua
├── doc/
│   └── fimloom.txt
├── tests/
│   ├── minimal_init.lua
│   ├── run.lua
│   ├── fixtures/
│   └── unit/
├── .github/
│   └── workflows/
│       └── ci.yml
├── CHANGELOG.md
├── CONTRIBUTING.md
├── IMPLEMENTATION_PLAN.md
├── LICENSE
├── README.md
└── stylua.toml
```

### Module responsibilities

| Module | Responsibility |
| --- | --- |
| `init.lua` | Public `setup`, enable, disable, status, and completion API |
| `config.lua` | Defaults, merge, validation, and immutable resolved config |
| `state.lua` | Runtime state and ownership records |
| `commands.lua` | `:FIMLoom` registration and subcommand completion |
| `completion.lua` | Debounce, request lifecycle, stale checks, prefix-consumption orchestration, and acceptance |
| `context.lua` | Safe prefix/suffix extraction and buffer metadata |
| `output.lua` | Completion normalization, overlap removal, bounds, and trailing-blank-line policy |
| `render.lua` | Extmarks, highlight setup, verified prefix consumption, multiline display, and cleanup |
| `transport.lua` | Async `curl`, JSON encoding, cancellation, and timeouts |
| `process.lua` | Health probing, server start, ownership, logs, and shutdown |
| `log.lua` | Bounded diagnostic log with configurable verbosity |
| `health.lua` | `:checkhealth fimloom` checks |
| `providers/*` | Provider-specific URLs, payloads, parsing, and health probes |

### Provider contract

Each provider module will expose a consistent internal interface similar to:

```lua
---@class FimLoomProvider
---@field name string
---@field health fun(config: table): FimLoomHttpRequest
---@field complete fun(context: table, config: table): FimLoomHttpRequest
---@field parse fun(response: table, config: table): string|nil, string|nil
```

The transport layer will know nothing about Ollama or llama.cpp. The completion
layer will know only the provider contract, not provider-specific JSON fields.

## 9. Provider Behavior

### Ollama

- Base endpoint: user configurable; default `http://127.0.0.1:11434`.
- Health/model discovery: `GET /api/tags`.
- FIM completion: `POST /api/generate`.
- Relevant request fields:
  - `model` from configuration;
  - `prompt` containing the prefix;
  - `suffix` containing the suffix;
  - `stream = false` for the MVP;
  - `options.num_predict` from `max_tokens`;
  - `options.temperature` from configuration.
- Response text: `response`.

The configured model must exist in Ollama. FIMLoom will not pull it
automatically.

### llama.cpp

- Base endpoint: user configurable; example `http://127.0.0.1:8012`.
- Health: `GET /health`.
- FIM completion: `POST /infill`.
- Relevant request fields:
  - `input_prefix`;
  - `input_suffix`;
  - optional `input_extra` in a later cross-file-context release;
  - `stream = false` for the MVP;
  - `n_predict` from `max_tokens`;
  - `temperature` from configuration.
- Response text will be parsed according to the current llama.cpp server
  response schema and covered by fixtures.

For llama.cpp, the actual loaded model is primarily selected in the server
startup command. The top-level `model` value exists so users can keep that
choice in their Neovim configuration and reference it safely from the command
function.

### Future chat fallback

An explicit `completion.mode = "chat"` may use Ollama `/api/chat` or a
llama.cpp OpenAI-compatible chat endpoint. It must instruct the model to return
only text that belongs between the prefix and suffix. This will not be silently
selected because chat responses can contain explanations and Markdown fences.

## 10. Context Collection

The context collector will capture:

- buffer number;
- absolute or project-relative filename when available;
- Neovim filetype;
- cursor row and byte column;
- buffer `changedtick`;
- bounded text before the cursor;
- bounded text after the cursor;
- indentation of the current line.

Rules:

- Work in byte offsets because Neovim cursor columns are byte-oriented.
- Preserve valid UTF-8 boundaries when trimming context.
- Prefer more prefix than suffix because recent code before the cursor is often
  the strongest completion signal.
- Never include unbounded buffers.
- Do not read unrelated files in the MVP.
- Skip unsuitable buffers: non-modifiable, readonly, binary, prompt, terminal,
  help, or buffers exceeding configured safety limits.
- Allow user-configurable filetype allow/deny lists.

## 11. Request Lifecycle and Concurrency

FIMLoom must assume that users type faster than a local model responds.

For every requested completion:

1. Increment a global request sequence number.
2. Cancel the prior active `curl` process if one exists.
3. Record buffer, window, cursor, changedtick, and request sequence.
4. Send the provider request asynchronously.
5. On callback, schedule Neovim API work onto the main loop.
6. Discard the response unless all recorded state remains valid.
7. Parse and sanitize the provider response.
8. Render only a non-empty completion that is not already present after the
   cursor.

Cancellation is an optimization; stale validation is the correctness
guarantee. A request may finish while cancellation is racing, so callback code
must still perform every stale check.

### Debouncing

- A libuv timer will wait `completion.debounce_ms` after `TextChangedI`.
- New typing stops and restarts the timer.
- Leaving Insert mode clears the timer, cancels the request, and removes ghost
  text.
- Manual completion bypasses the debounce delay.
- No automatic request will run while a completion popup is visible unless the
  user enables that behavior explicitly.

## 12. Ghost-Text Rendering

Rendering will use a dedicated Neovim namespace and buffer extmarks.

- The first line will use inline virtual text at the cursor.
- Additional lines will use virtual lines or related extmark capabilities.
- A dedicated `FIMLoomSuggestion` highlight uses a neutral GUI/terminal grey,
  supports direct attributes or linking, respects existing definitions, and is
  restored after colorscheme changes only when absent.
- Only one active suggestion will exist per Neovim instance in the MVP.
- Exact insertions at the anchor consume the visible prefix and re-anchor the
  remaining ghost text. Mismatch, deletion, cursor movement away from the
  anchor, buffer changes, InsertLeave, disable, and errors clear it.
- Accepting inserts real buffer text as one undo-friendly edit.
- The renderer will never modify the buffer merely to preview a suggestion.

Response cleanup will:

- normalize line endings;
- remove accidental Markdown code fences in fallback modes;
- remove text already duplicated by the suffix;
- remove trailing whitespace-only lines when configured while preserving
  internal blank lines;
- enforce configured character/line limits;
- preserve intentional indentation;
- reject empty or whitespace-only results.

## 13. HTTP Transport

The MVP transport will execute `curl` with `vim.system()` using an argument
array and JSON on standard input.

Required properties:

- asynchronous execution;
- explicit connect and overall timeouts;
- request cancellation by terminating the `curl` process;
- stdout and stderr captured separately;
- bounded response size;
- HTTP status captured without confusing it with response JSON;
- useful errors for connection refusal, timeout, malformed JSON, and provider
  failures;
- no shell invocation;
- request content excluded from logs unless a future opt-in setting is added.

Using `curl` is a deliberate initial tradeoff: it is mature, supports streaming
later, and avoids implementing an HTTP parser in plugin code. A native libuv
transport can be considered after the behavior is stable.

## 14. Server Process Lifecycle

### Startup algorithm

1. Probe the configured provider health endpoint.
2. If healthy, mark the server as available and **not owned**.
3. If unhealthy and `auto_start = false`, report a helpful connection error.
4. If unhealthy and `auto_start = true`, resolve the configured argv command.
5. Start the process directly with `jobstart()` and retain its job identifier.
6. Mark ownership only after process creation succeeds.
7. Poll the health endpoint with backoff until ready, the process exits, or the
   startup timeout expires.
8. Capture a bounded tail of stdout/stderr for diagnostics.

### Shutdown algorithm

On `VimLeavePre`, explicit disable when configured, or `:FIMLoom stop`:

1. Cancel timers and completion requests.
2. Check that the process is marked as owned by this Neovim instance.
3. Call `jobstop()` so Neovim terminates the managed process group.
4. Never search for and kill processes by executable name or port.
5. Never kill a pre-existing process merely because its endpoint matches.

`jobstop()` sends `SIGTERM` and applies Neovim's bounded `SIGKILL` fallback when
the job does not exit. The exit autocmd must remain fast and reliable.

The job-control API is deliberate. For the supported Neovim releases,
terminating a `vim.system()` process can leave descendants running, while
`jobstart()` and `jobstop()` preserve Neovim's process-group cleanup behavior.
The HTTP transport still uses `vim.system()` because each request owns only a
direct `curl` process.

### Known lifecycle limitations

- `VimLeavePre` handles normal Neovim exits, not `SIGKILL` or machine failure.
- With several Neovim instances, the instance that owns the server cannot yet
  know whether another instance still needs it. `auto_stop = false` is the safe
  shared-server configuration for `v0.1.x`; compatible llama.cpp builds can
  combine it with `--sleep-idle-seconds` to unload idle model weights.
- Wrapping the startup command in `sh -c` can detach grandchildren and is
  intentionally unsupported.

## 15. State Model

Runtime state will be private and centralized:

```lua
{
  configured = false,
  enabled = false,
  shutting_down = false,
  request_seq = 0,
  active_request = nil,
  debounce_timer = nil,
  suggestion = nil,
  server = {
    status = "unknown", -- unknown | starting | ready | stopped | failed
    owned = false,
    process = nil,
    started_command = nil,
  },
}
```

State transitions will go through functions rather than being mutated from
arbitrary modules. Cleanup operations must be idempotent.

## 16. Diagnostics and Health Checks

`:checkhealth fimloom` will report:

- supported Neovim version;
- whether `curl` is executable;
- configured provider;
- normalized endpoint;
- whether a model is configured;
- endpoint reachability;
- provider-specific health result;
- whether the startup executable exists;
- server ownership/status;
- configuration warnings;
- log file location when logging is enabled.

Diagnostics must not print full buffer context or secrets. Endpoint and model
names are acceptable, while request bodies are private by default.

## 17. Error Handling

Errors fall into three classes:

1. **Configuration errors**
   Fail early during `setup()` with the invalid key and expected value.

2. **Recoverable runtime errors**
   Connection refusal, timeout, and temporary provider failures should clear the
   suggestion, update status, and avoid noisy notifications on every keystroke.

3. **User-requested operation errors**
   Manual completion, start, stop, and status commands may display a concise
   notification with a path to detailed logs.

Automatic requests will use rate-limited notifications. Repeated failures will
temporarily back off instead of spawning a failing request after every change.

## 18. Security and Privacy

- Default examples bind inference servers to `127.0.0.1`.
- FIMLoom will send code only to the configured endpoint.
- No telemetry or analytics will be implemented.
- Startup uses argv arrays, not shell evaluation.
- Logs exclude source context and full response text by default.
- The plugin will not read environment secrets it does not need.
- The README will warn that configuring a remote endpoint sends code to that
  remote system even though FIMLoom itself is local-first.
- Automatic model pulling is excluded because it downloads large files and
  changes the user's system state.

## 19. Testing Strategy

### Unit tests

- default configuration and deep merge;
- validation errors;
- endpoint normalization;
- UTF-8-safe context trimming;
- Ollama payload creation and response parsing;
- llama.cpp payload creation and response parsing;
- completion cleanup and suffix deduplication;
- stale-response checks;
- process ownership decisions;
- idempotent cleanup.

### Headless integration tests

- load plugin with a minimal config;
- create commands and autocmds once;
- render and clear a fake suggestion;
- accept single-line and multiline suggestions;
- ensure disabled mode does not request completions;
- mock transport responses without requiring a model in CI.

### Manual test matrix

| Scenario | Expected result |
| --- | --- |
| Ollama already running | Connect; do not claim ownership; do not stop on exit |
| Ollama stopped with auto-start | Start, become healthy, complete, stop on exit |
| llama.cpp already running | Connect through `/infill`; leave it running on exit |
| llama.cpp stopped with auto-start | Start configured model; stop owned process on exit |
| Invalid endpoint | Non-blocking useful error and health failure |
| Missing `curl` | Setup remains safe; health explains the missing dependency |
| Slow response followed by typing | Old response is discarded |
| Buffer switch during request | Response is discarded |
| Multiline completion | Preview renders and accepts correctly |
| Existing completion popup | FIMLoom respects configured conflict behavior |
| Two Neovim instances | Documented shared-server limitation is respected |

Real Ollama and llama.cpp smoke tests will be optional because CI should not
download models.

## 20. Documentation Plan

`README.md` will contain:

1. What FIMLoom is and what it is not.
2. Short demo or GIF after the UI is stable.
3. Requirements.
4. Installation with `lazy.nvim`.
5. Quick starts for Ollama and llama.cpp.
6. Model-selection guidance.
7. Complete configuration reference.
8. Keymaps and commands.
9. Server ownership and shutdown behavior.
10. Privacy explanation.
11. Troubleshooting and `:checkhealth fimloom`.
12. Development and testing commands.
13. Roadmap, contributing, license, and acknowledgements.

`doc/fimloom.txt` will provide native `:help fimloom` documentation. The README
and help file must describe behavior consistently.

## 21. Licensing and Attribution

The project will use the MIT License with copyright attributed to Ankur Kumar.

Reference implementations and documentation will be studied for architecture
and API usage. Code copied or adapted from another project, if any, must be
compatible with MIT and receive clear attribution in the relevant file and
acknowledgements. The preferred approach is an original implementation based on
public API documentation.

Planned acknowledgements:

- `codeium.el` for completion-client architecture ideas;
- `llama.vim` and other local-completion projects for ecosystem context;
- Ollama and llama.cpp for local inference APIs;
- Neovim and `lazy.nvim` documentation.

“Copilot” will be used only as a familiar feature comparison, not in the
product name, logo, or repository identity.

## 22. Staged Implementation and Commit Plan

Every stage must remain independently reviewable. A stage is committed only
after its checks pass.

### Stage 0 — Planning

Files:

- `IMPLEMENTATION_PLAN.md`

Review gate:

- scope, architecture, provider strategy, lifecycle rules, and name approved.

Commit:

```text
docs: define the FIMLoom implementation plan

Document the MVP scope, architecture, provider contracts, process lifecycle,
testing strategy, release stages, and explicit non-goals for the local-first
Neovim completion plugin.
```

### Stage 1 — Repository foundation

Files:

- plugin/Lua skeleton;
- MIT `LICENSE`;
- `stylua.toml`;
- minimal test runner;
- initial `.gitignore` and editor settings.

Checks:

- plugin loads in headless Neovim;
- formatting passes;
- `require("fimloom").setup({})` exists without starting a server yet.

Commit:

```text
chore: scaffold the FIMLoom plugin

Add the Lua module layout, plugin entry point, formatting configuration,
minimal headless test harness, and MIT license.
```

### Stage 2 — Configuration and provider contract

Files:

- `config.lua`, `state.lua`, and provider registry;
- configuration tests.

Checks:

- defaults are not mutated;
- invalid provider, model, endpoint, and command values fail clearly;
- custom endpoints and models resolve correctly.

Commit:

```text
feat(config): add validated local model configuration

Introduce immutable defaults, endpoint and model selection, startup command
validation, provider registration, and focused configuration tests.
```

### Stage 3 — Async transport

Files:

- `transport.lua` and transport tests.

Checks:

- JSON request succeeds against a fixture server;
- cancellation works;
- timeouts, HTTP errors, and malformed JSON are distinguished;
- no shell command is used.

Commit:

```text
feat(transport): add cancellable asynchronous HTTP requests

Use vim.system and curl to send JSON requests without blocking Neovim, with
timeouts, cancellation, bounded output, and structured errors.
```

### Stage 4 — Ollama and llama.cpp providers

Files:

- `providers/ollama.lua`;
- `providers/llamacpp.lua`;
- request/response fixtures and tests.

Checks:

- exact payloads match current documented APIs;
- native FIM responses parse cleanly;
- custom local ports work.

Commit:

```text
feat(providers): support Ollama and llama.cpp infilling

Add provider-specific health checks, FIM payloads, response parsing, endpoint
normalization, and fixture-backed tests for both local inference servers.
```

### Stage 5 — Completion pipeline and ghost text

Files:

- `context.lua`, `completion.lua`, and `render.lua`;
- buffer and stale-response tests.

Checks:

- typing is never blocked;
- new requests cancel old requests;
- stale responses never render;
- single-line and multiline suggestions preview and accept correctly;
- normal editing behavior remains intact.

Commit:

```text
feat(completion): add debounced inline ghost-text suggestions

Collect bounded cursor context, request completions asynchronously, reject
stale responses, render extmark previews, and support safe acceptance and
dismissal.
```

### Stage 6 — Managed server lifecycle

Files:

- `process.lua`, lifecycle integration, and ownership tests.

Checks:

- pre-existing server is never stopped;
- configured argv command starts successfully;
- readiness polling times out cleanly;
- owned process stops on normal Neovim exit;
- cleanup remains idempotent.

Commit:

```text
feat(server): manage owned local inference processes

Probe provider health, start configured Ollama or llama.cpp commands, track
process ownership, capture bounded diagnostics, and stop only owned servers on
normal Neovim exit.
```

### Stage 7 — Commands, health, and diagnostics

Files:

- `commands.lua`, `health.lua`, and `log.lua`.

Checks:

- every public command works;
- `:checkhealth fimloom` provides actionable results;
- automatic failures are rate-limited;
- logs do not expose source context by default.

Commit:

```text
feat(diagnostics): add controls and health reporting

Provide FIMLoom subcommands, Neovim health checks, status reporting, bounded
logs, and rate-limited runtime diagnostics.
```

### Stage 8 — Documentation and release hardening

Files:

- complete `README.md`;
- `doc/fimloom.txt`;
- `CONTRIBUTING.md`, `CHANGELOG.md`, and CI workflow.

Checks:

- clean installation works through local `dir` and public lazy.nvim specs;
- both provider quick starts are manually verified;
- tests and formatting pass in CI;
- help tags generate successfully;
- documentation matches actual defaults.

Commit:

```text
docs: prepare FIMLoom v0.1.0 for public use

Add complete installation, configuration, provider, lifecycle, privacy,
troubleshooting, development, and release documentation with automated checks.
```

### Stage 9 — Public release

Actions performed by the repository owner:

- create the public GitHub repository;
- add and verify the remote;
- push `main`;
- inspect the public README and license;
- create annotated tag `v0.1.0`;
- publish release notes from `CHANGELOG.md`.

No GitHub account access is required by ChatGPT. Exact commands will be
provided for the repository owner to run locally.

Commit policy:

- no unrelated changes in a stage;
- no generated model files, logs, sockets, or secrets committed;
- detailed body explains the reason and behavior, not only filenames;
- fix a stage before starting the next stage;
- avoid rewriting already published history.

## 23. Definition of Done for `v0.1.0`

The release is complete when all of the following are true:

- a new user can install FIMLoom with `lazy.nvim` from the public repository;
- the user can choose Ollama or llama.cpp and set any appropriate local port;
- the model is selected in Neovim configuration;
- an already-running server can be used without being claimed or killed;
- a configured stopped server can be started automatically;
- an owned server terminates during a normal Neovim exit;
- typing produces cancellable, non-blocking inline suggestions;
- stale completions never appear after later edits;
- suggestions can be accepted and dismissed safely;
- `:checkhealth fimloom` diagnoses common configuration and dependency issues;
- tests and formatting pass;
- README, help, license, changelog, and contribution instructions are complete;
- the repository contains no credentials, local model files, or machine-specific
  artifacts beyond clearly marked examples.

## 24. Post-MVP Roadmap

Potential follow-up releases, ordered roughly by value:

1. Incremental streaming suggestions.
2. Explicit chat/instruction-model fallback.
3. Nearby/open-buffer and repository context through `input_extra`.
4. Multiple-Neovim server leases and shared ownership coordination.
5. Partial suggestion acceptance by word or line.
6. `nvim-cmp` and `blink.cmp` integrations.
7. Per-filetype models and generation settings.
8. Native libuv HTTP transport experiment.
9. Windows process management.
10. Performance telemetry stored locally and disabled by default.

Roadmap items are not promises and should not complicate the MVP architecture.

## 25. Primary References

- Neovim documentation: <https://neovim.io/doc/>
- Lua documentation: <https://www.lua.org/docs.html>
- lazy.nvim plugin specification: <https://lazy.folke.io/spec>
- Ollama generate API: <https://docs.ollama.com/api/generate>
- llama.cpp server API: <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- codeium.el: <https://github.com/Exafunction/codeium.el>
- llama.vim: <https://github.com/ggml-org/llama.vim>

These references describe external APIs and architectural precedents. FIMLoom
will remain an original implementation with its own tests and documentation.
