return function(t)
  local config = require("fimloom.config")

  t.test("Ollama defaults resolve without mutating defaults", function()
    local first = config.resolve()
    local second = config.resolve()

    t.assert_equal(first.provider, "ollama")
    t.assert_equal(first.endpoint, "http://127.0.0.1:11434")
    t.assert_equal(first.completion.mode, "fim")
    t.assert_equal(first.completion.trim_trailing_blank_lines, true)
    t.assert_equal(first.completion.preserve_matching_prefix, true)
    t.assert_equal(first.ui.suggestion.fg, "#808080")
    t.assert_equal(first.ui.suggestion.ctermfg, 244)
    t.assert_equal(first.server.auto_start, false)
    t.assert_equal(first.log.level, "warn")
    t.assert_equal(first.log.file, false)

    first.completion.context.max_prefix_bytes = 1
    t.assert_equal(second.completion.context.max_prefix_bytes, 12000)
    t.assert_equal(config.defaults().completion.context.max_prefix_bytes, 12000)
  end)

  t.test("llama.cpp selects its provider default endpoint", function()
    local resolved = config.resolve({
      provider = "llamacpp",
      model = "/models/qwen.gguf",
    })

    t.assert_equal(resolved.endpoint, "http://127.0.0.1:8012")
    t.assert_equal(resolved.model, "/models/qwen.gguf")
  end)

  t.test("custom endpoint ports are preserved and trailing slashes removed", function()
    local resolved = config.resolve({
      endpoint = "http://127.0.0.1:45678///",
      model = "local-code-model",
    })

    t.assert_equal(resolved.endpoint, "http://127.0.0.1:45678")
    t.assert_equal(resolved.model, "local-code-model")
  end)

  t.test("resolved options are independent from the user table", function()
    local options = {
      completion = {
        generation = {
          max_tokens = 64,
        },
      },
    }
    local resolved = config.resolve(options)

    options.completion.generation.max_tokens = 1
    t.assert_equal(resolved.completion.generation.max_tokens, 64)
  end)

  t.test("unknown providers fail with an actionable path", function()
    t.assert_error(function()
      config.resolve({ provider = "missing" })
    end, "provider has unknown provider")
  end)

  t.test("endpoint validation rejects unsupported schemes", function()
    t.assert_error(function()
      config.resolve({ endpoint = "ftp://127.0.0.1:11434" })
    end, "endpoint must be an HTTP or HTTPS URL")
  end)

  t.test("endpoint validation rejects query strings", function()
    t.assert_error(function()
      config.resolve({ endpoint = "http://127.0.0.1:11434?token=secret" })
    end, "endpoint must not contain a query string or fragment")

    t.assert_error(function()
      config.resolve({ endpoint = "http://secret@127.0.0.1:11434" })
    end, "endpoint must not contain embedded user information")
  end)

  t.test("model must be non-empty when provided", function()
    t.assert_error(function()
      config.resolve({ model = "  " })
    end, "model must be a non-empty string")
  end)

  t.test("startup commands accept argument arrays", function()
    local resolved = config.resolve({
      server = {
        command = { "ollama", "serve" },
      },
    })

    t.assert_deep_equal(resolved.server.command, { "ollama", "serve" })
  end)

  t.test("startup commands reject shell strings and empty arrays", function()
    t.assert_error(function()
      config.resolve({ server = { command = "ollama serve" } })
    end, "server.command must be a non-empty argument list")

    t.assert_error(function()
      config.resolve({ server = { command = {} } })
    end, "server.command must be a non-empty argument list")
  end)

  t.test("automatic startup requires an explicit command", function()
    t.assert_error(function()
      config.resolve({ server = { auto_start = true } })
    end, "server.command must be configured when server.auto_start is true")

    local resolved = config.resolve({
      server = {
        auto_start = true,
        command = function()
          return { "ollama", "serve" }
        end,
      },
    })
    t.assert_equal(type(resolved.server.command), "function")
  end)

  t.test("diagnostic configuration is validated", function()
    local resolved = config.resolve({
      log = {
        level = "debug",
        file = "~/.local/state/nvim/fimloom.log",
        max_entries = 50,
        max_file_bytes = 4096,
        notify = false,
        notify_cooldown_ms = 100,
      },
    })
    t.assert_equal(resolved.log.level, "debug")
    t.assert_equal(resolved.log.file, "~/.local/state/nvim/fimloom.log")

    t.assert_error(function()
      config.resolve({ log = { level = "trace" } })
    end, "log.level must be one of")
    t.assert_error(function()
      config.resolve({ log = { file = {} } })
    end, "log.file must be a non-empty string")
    t.assert_error(function()
      config.resolve({ log = { notify_cooldown_ms = -1 } })
    end, "log.notify_cooldown_ms must be between")
  end)

  t.test("numeric completion options enforce safe ranges", function()
    t.assert_error(function()
      config.resolve({ completion = { debounce_ms = -1 } })
    end, "completion.debounce_ms must be between")

    t.assert_error(function()
      config.resolve({ completion = { generation = { temperature = 3 } } })
    end, "completion.generation.temperature must be between")

    t.assert_error(function()
      config.resolve({ completion = { preview = { max_lines = 0 } } })
    end, "completion.preview.max_lines must be between")
  end)

  t.test("completion interaction and suggestion highlight options are validated", function()
    local resolved = config.resolve({
      completion = {
        trim_trailing_blank_lines = false,
        preserve_matching_prefix = false,
      },
      ui = {
        suggestion = {
          fg = "#707070",
          ctermfg = 242,
          italic = true,
        },
        suggestion_hl = "Comment",
      },
    })
    t.assert_equal(resolved.completion.trim_trailing_blank_lines, false)
    t.assert_equal(resolved.completion.preserve_matching_prefix, false)
    t.assert_equal(resolved.ui.suggestion.fg, "#707070")
    t.assert_equal(resolved.ui.suggestion_hl, "Comment")

    t.assert_error(function()
      config.resolve({ completion = { preserve_matching_prefix = "yes" } })
    end, "completion.preserve_matching_prefix must be a boolean")
    t.assert_error(function()
      config.resolve({ ui = { suggestion = { ctermfg = 300 } } })
    end, "ui.suggestion.ctermfg must be between")
    t.assert_error(function()
      config.resolve({ ui = { suggestion_hl = "" } })
    end, "ui.suggestion_hl must be a non-empty string")
  end)

  t.test("nested configuration sections must remain tables", function()
    t.assert_error(function()
      config.resolve({ completion = false })
    end, "completion must be a table")

    t.assert_error(function()
      config.resolve({ server = "ollama serve" })
    end, "server must be a table")
  end)

  t.test("context filetype lists are validated and copied", function()
    local options = {
      completion = {
        context = {
          filetypes = {
            allow = { "lua", "rust" },
            deny = { "markdown" },
          },
        },
      },
    }
    local resolved = config.resolve(options)

    options.completion.context.filetypes.allow[1] = "changed"
    t.assert_deep_equal(resolved.completion.context.filetypes.allow, { "lua", "rust" })
    t.assert_deep_equal(resolved.completion.context.filetypes.deny, { "markdown" })

    t.assert_error(function()
      config.resolve({ completion = { context = { filetypes = { allow = "lua" } } } })
    end, "completion.context.filetypes.allow must be a list of strings")
  end)

  t.test("keymaps can be disabled explicitly", function()
    local resolved = config.resolve({
      keymaps = {
        accept = false,
        dismiss = false,
        manual = false,
      },
    })

    t.assert_equal(resolved.keymaps.accept, false)
    t.assert_equal(resolved.keymaps.dismiss, false)
    t.assert_equal(resolved.keymaps.manual, false)
  end)
end
