# Contributing to FIMLoom.nvim

Thank you for helping improve local-first code completion for Neovim.

FIMLoom is intentionally small in `v0.1.x`. Changes should preserve its
asynchronous editing path, explicit privacy boundary, and strict ownership of
only the processes it starts.

## Before opening a change

- Search existing issues and pull requests once the public repository exists.
- Keep one focused problem or feature per change.
- Discuss large API, provider, UI, lifecycle, or scope changes before investing
  in an implementation.
- Do not include model files, generated logs, credentials, private source-code
  context, or machine-specific artifacts.

Be respectful and constructive in all project discussions. Harassment,
personal attacks, and discriminatory behavior are not acceptable.

## Development requirements

- Neovim 0.10 or newer.
- `curl`.
- [StyLua](https://github.com/JohnnyMorganz/StyLua).
- Git.

Clone the repository and use it directly from lazy.nvim while developing:

```lua
{
  dir = "/absolute/path/to/fimloom.nvim",
  event = "InsertEnter",
  cmd = "FIMLoom",
  main = "fimloom",
  opts = {
    provider = "ollama",
    model = "YOUR_INSTALLED_FIM_MODEL",
  },
}
```

## Required checks

Run these from the repository root before submitting a change:

```sh
stylua lua plugin tests
stylua --check lua plugin tests
git diff --check
nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua
```

For documentation changes, also validate native help:

```sh
nvim --headless --clean -u tests/minimal_init.lua \
  -c "helptags doc" \
  -c "silent help fimloom" \
  -c "quitall"
rm -f doc/tags
```

CI runs the headless suite on the minimum supported Neovim release and the
current stable release. It also checks StyLua formatting and Vim help tags.

## Test design

- Add a focused regression test for every behavior change or bug fix.
- Prefer dependency injection already exposed by modules over global mocks.
- Keep unit tests deterministic and independent of user configuration.
- Use the loopback HTTP fixture for transport/provider integration behavior.
- Do not download models or require Ollama/llama.cpp in automated tests.
- Verify cancellation, idempotent cleanup, stale-response rejection, and
  ownership boundaries whenever those paths are affected.
- Ensure tests clean up buffers, timers, jobs, commands, autocmds, and files.

The lightweight harness lives in `tests/helpers.lua`; suites are registered in
`tests/run.lua`.

## Provider contributions

Provider-specific behavior belongs under `lua/fimloom/providers/`. An adapter
must expose:

```lua
{
  name = "provider-name",
  default_endpoint = "http://127.0.0.1:PORT",
  health_request = function(config) end,
  completion_request = function(context, config) end,
  parse_health = function(response, config) end,
  parse_completion = function(response) end,
}
```

A provider change must include request mapping, response validation, health,
custom-port, structured-error, and cancellation tests. New adapters must not
silently introduce cloud authentication, telemetry, model downloads, or source
logging.

## Process-lifecycle changes

Lifecycle changes are high risk. They must preserve these invariants:

1. Probe before starting a command.
2. Execute argv lists without a shell.
3. Never claim or stop an already-running external server.
4. Enforce a bounded readiness deadline.
5. Stop owned work after failure and during configured normal-exit cleanup.
6. Keep shutdown idempotent.

Include a real child-process test when behavior cannot be proven with injected
job functions alone.

## Documentation

Update both `README.md` and `doc/fimloom.txt` when public behavior, defaults,
commands, mappings, privacy, provider setup, or troubleshooting changes.

- Keep examples safe and copyable.
- Use loopback addresses by default.
- Never imply that FIMLoom downloads a model.
- Clearly distinguish external from FIMLoom-owned servers.
- Keep the public GitHub owner and release information current.
- Do not commit generated `doc/tags`; plugin managers generate it.

Add user-visible changes to `CHANGELOG.md` under `[Unreleased]`.

## Manual provider checks

Real model tests are intentionally outside CI. Before a release, test at least:

| Scenario | Expected result |
| --- | --- |
| Ollama already running | Ready and unowned; not stopped on exit. |
| Ollama managed by FIMLoom | Starts, completes, and stops on normal exit. |
| llama.cpp already running | Uses `/infill`; remains external. |
| llama.cpp managed by FIMLoom | Starts the configured GGUF and stops cleanly. |
| Detached llama.cpp shared by editors | One editor can exit; idle sleep releases model weights. |
| Slow request followed by typing | Older request is cancelled/ignored. |
| Buffer or cursor change | Stale response is ignored. |
| Multiline completion | Preview and one-edit acceptance are correct. |
| Existing accept mapping | FIMLoom claims the configured key while enabled. |
| Existing dismiss/manual mapping | FIMLoom leaves the mapping unchanged. |
| Non-loopback endpoint | Health reports the privacy boundary. |

Record provider versions, model names, operating system, and Neovim version in
the release notes or test report. Do not attach source-bearing request logs.

## Commit and pull-request guidance

- Use imperative, scoped commit subjects where practical.
- Explain motivation and behavior in the commit body.
- Avoid unrelated formatting or refactors.
- Keep generated files and local runtime artifacts out of commits.
- Describe user-visible changes, tests run, manual checks, compatibility impact,
  and privacy/lifecycle implications in the pull request.

By contributing, you agree that your contribution may be distributed under the
project's [MIT License](LICENSE).
