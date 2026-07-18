return function(t)
  local config = require("fimloom.config")
  local health = require("fimloom.health")

  local function fake_state(resolved, server)
    return {
      is_configured = function()
        return resolved ~= nil
      end,
      get_config = function()
        return vim.deepcopy(resolved)
      end,
      get_server = function()
        return vim.deepcopy(server or {
          status = "ready",
          owned = false,
        })
      end,
    }
  end

  local function message_text(report)
    local messages = {}
    for _, result in ipairs(report) do
      messages[#messages + 1] = result.message
      if type(result.advice) == "string" then
        messages[#messages + 1] = result.advice
      end
    end
    return table.concat(messages, "\n")
  end

  local function dependencies(resolved, provider_result)
    return {
      state = fake_state(resolved),
      providers = {
        health = function(_, callback)
          local request = { cancelled = false }
          function request:cancel()
            self.cancelled = true
            return true
          end
          vim.schedule(function()
            if not request.cancelled then
              callback(vim.deepcopy(provider_result))
            end
          end)
          return request
        end,
      },
      log = {
        status = function()
          return {
            configured = true,
            level = "warn",
            entry_count = 0,
            file = "/tmp/fimloom.log",
          }
        end,
      },
      has = function()
        return 1
      end,
      executable = function()
        return 1
      end,
      version = function()
        return { major = 0, minor = 12, patch = 4 }
      end,
    }
  end

  t.test("health collection reports a ready local provider and installed model", function()
    local resolved = config.resolve({
      provider = "ollama",
      model = "qwen2.5-coder:3b",
      server = {
        command = { "ollama", "serve" },
      },
    })
    local report = health.collect(dependencies(resolved, {
      ok = true,
      ready = true,
      model_available = true,
    }))
    local messages = message_text(report)

    assert(messages:find("Neovim 0.12.4 is supported", 1, true), messages)
    assert(messages:find("curl is executable", 1, true), messages)
    assert(messages:find("loopback-local", 1, true), messages)
    assert(messages:find("Startup executable is available: ollama", 1, true), messages)
    assert(messages:find("Provider endpoint is reachable and ready", 1, true), messages)
    assert(messages:find("configured Ollama model is installed", 1, true), messages)
    assert(messages:find("Diagnostic log: /tmp/fimloom.log", 1, true), messages)
  end)

  t.test("health collection gives actionable setup, dependency, and privacy failures", function()
    local report = health.collect({
      state = fake_state(nil),
      log = {
        status = function()
          return { configured = false, level = "off", entry_count = 0 }
        end,
      },
      has = function()
        return 0
      end,
      executable = function()
        return 0
      end,
      version = function()
        return { major = 0, minor = 9, patch = 5 }
      end,
    })
    local messages = message_text(report)
    assert(messages:find("unsupported", 1, true), messages)
    assert(messages:find("curl is not executable", 1, true), messages)
    assert(messages:find("setup has not run", 1, true), messages)
    assert(messages:find("require('fimloom').setup", 1, true), messages)

    local remote = config.resolve({ endpoint = "http://192.168.1.50:11434" })
    report = health.collect({
      state = fake_state(
        remote,
        { status = "failed", owned = false, error = { kind = "connection" } }
      ),
      providers = {
        health = function()
          error("provider probe must be skipped when curl is missing")
        end,
      },
      log = {
        status = function()
          return { configured = true, level = "warn", entry_count = 0 }
        end,
      },
      has = function()
        return 1
      end,
      executable = function()
        return 0
      end,
      version = function()
        return { major = 0, minor = 12, patch = 4 }
      end,
    })
    messages = message_text(report)
    assert(messages:find("not loopback-local", 1, true), messages)
    assert(messages:find("No Ollama model is configured", 1, true), messages)
    assert(messages:find("Last server error category: connection", 1, true), messages)
  end)

  t.test("health provider failures exclude request context and give recovery advice", function()
    local resolved = config.resolve({
      provider = "llamacpp",
      model = "/models/code.gguf",
    })
    local report = health.collect(dependencies(resolved, {
      ok = false,
      error = {
        kind = "connection",
        message = "connection refused",
      },
      prefix = "PRIVATE PREFIX",
      suffix = "PRIVATE SUFFIX",
    }))
    local messages = message_text(report)

    assert(messages:find("Provider health failed (connection)", 1, true), messages)
    assert(messages:find(":FIMLoom status", 1, true), messages)
    assert(not messages:find("PRIVATE", 1, true), messages)
    t.assert_equal(type(health.check), "function")
  end)

  t.test(":checkhealth fimloom discovers and renders the health module", function()
    local previous = vim.api.nvim_get_current_buf()
    vim.cmd("checkhealth fimloom")
    local health_buffer = vim.api.nvim_get_current_buf()
    local output = table.concat(vim.api.nvim_buf_get_lines(health_buffer, 0, -1, false), "\n")

    assert(output:find("FIMLoom.nvim", 1, true), output)
    assert(output:find("setup has not run", 1, true), output)

    if health_buffer ~= previous and vim.api.nvim_buf_is_valid(health_buffer) then
      vim.api.nvim_buf_delete(health_buffer, { force = true })
    end
    if vim.api.nvim_buf_is_valid(previous) then
      vim.api.nvim_set_current_buf(previous)
    end
  end)
end
