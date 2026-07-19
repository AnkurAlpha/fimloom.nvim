local fixture = require("tests.fixtures.http_server")

return function(t)
  local config = require("fimloom.config")
  local providers = require("fimloom.providers")
  local llamacpp = require("fimloom.providers.llamacpp")
  local ollama = require("fimloom.providers.ollama")

  local function perform(operation, wait_ms)
    local result
    local request = operation(function(response)
      result = response
    end)
    local completed = vim.wait(wait_ms or 3000, function()
      return result ~= nil
    end, 10)

    assert(completed, "provider callback did not complete before the test timeout")
    return result, request
  end

  local function with_server(handler, callback)
    local server = fixture.start(handler)
    local ok, error_message = xpcall(function()
      callback(server)
    end, debug.traceback)

    server.stop()
    if not ok then
      error(error_message)
    end
  end

  t.test("built-in adapters implement the provider contract", function()
    for _, name in ipairs({ "ollama", "llamacpp" }) do
      local provider = assert(providers.get(name))
      t.assert_equal(type(provider.health_request), "function")
      t.assert_equal(type(provider.completion_request), "function")
      t.assert_equal(type(provider.parse_health), "function")
      t.assert_equal(type(provider.parse_completion), "function")
    end
  end)

  t.test("Ollama maps FIM context and generation settings to /api/generate", function()
    local resolved = config.resolve({
      provider = "ollama",
      endpoint = "http://127.0.0.1:24680/",
      model = "qwen2.5-coder:7b",
      completion = {
        generation = {
          max_tokens = 77,
          temperature = 0.1,
        },
      },
    })
    local request = ollama.completion_request({
      prefix = "local answer = ",
      suffix = "\nreturn answer",
    }, resolved)

    t.assert_equal(request.method, "POST")
    t.assert_equal(request.url, "http://127.0.0.1:24680/api/generate")
    t.assert_deep_equal(request.body, {
      model = "qwen2.5-coder:7b",
      prompt = "local answer = ",
      suffix = "\nreturn answer",
      stream = false,
      think = false,
      options = {
        num_predict = 77,
        temperature = 0.1,
      },
    })
  end)

  t.test("llama.cpp maps FIM context and generation settings to /infill", function()
    local resolved = config.resolve({
      provider = "llamacpp",
      endpoint = "http://127.0.0.1:13579",
      completion = {
        generation = {
          max_tokens = 96,
          temperature = 0.35,
        },
      },
    })
    local request = llamacpp.completion_request({
      prefix = "fn main() {",
      suffix = "}",
    }, resolved)

    t.assert_equal(request.method, "POST")
    t.assert_equal(request.url, "http://127.0.0.1:13579/infill")
    t.assert_deep_equal(request.body, {
      input_prefix = "fn main() {",
      input_suffix = "}",
      stream = false,
      cache_prompt = true,
      n_predict = 96,
      temperature = 0.35,
    })
  end)

  t.test("provider health requests and parsers use native endpoints", function()
    local ollama_config = config.resolve({
      provider = "ollama",
      model = "deepseek-coder:latest",
    })
    local llama_config = config.resolve({ provider = "llamacpp" })
    local ollama_health = ollama.health_request(ollama_config)
    local llama_health = llamacpp.health_request(llama_config)
    local ollama_result = assert(ollama.parse_health({
      models = {
        { name = "deepseek-coder:latest" },
      },
    }, ollama_config))
    local llama_result = assert(llamacpp.parse_health({ status = "ok" }))

    t.assert_equal(ollama_health.url, "http://127.0.0.1:11434/api/tags")
    t.assert_equal(llama_health.url, "http://127.0.0.1:8012/health")
    t.assert_equal(ollama_result.ready, true)
    t.assert_equal(ollama_result.model_available, true)
    t.assert_equal(llama_result.ready, true)
  end)

  t.test("provider parsers reject malformed native responses", function()
    local health, health_error = ollama.parse_health({}, config.resolve({ provider = "ollama" }))
    local ollama_text, ollama_error = ollama.parse_completion({ done = true })
    local llama_text, llama_error = llamacpp.parse_completion({ stop = true })

    t.assert_equal(health, nil)
    assert(health_error:find("models list", 1, true), health_error)
    t.assert_equal(ollama_text, nil)
    assert(ollama_error:find("completion text", 1, true), ollama_error)
    t.assert_equal(llama_text, nil)
    assert(llama_error:find("completion text", 1, true), llama_error)
  end)

  t.test("Ollama completions work through a custom loopback port", function()
    with_server(function(request)
      if request.path == "/api/generate" then
        return 200, vim.json.encode({ response = "42", done = true })
      end

      return 404, vim.json.encode({ error = "not found" })
    end, function(server)
      local resolved = config.resolve({
        provider = "ollama",
        endpoint = server.url,
        model = "local-coder",
      })
      local result, request = perform(function(callback)
        return providers.complete({ prefix = "answer = ", suffix = "\n" }, resolved, callback)
      end)
      local received = vim.json.decode(server.requests[1].body)

      t.assert_equal(result.ok, true)
      t.assert_equal(result.provider, "ollama")
      t.assert_equal(result.text, "42")
      t.assert_equal(request:is_done(), true)
      t.assert_equal(server.requests[1].path, "/api/generate")
      t.assert_equal(received.model, "local-coder")
      t.assert_equal(received.prompt, "answer = ")
      t.assert_equal(received.think, false)
    end)
  end)

  t.test("llama.cpp completions work through a custom loopback port", function()
    with_server(function(request)
      if request.path == "/infill" then
        return 200, vim.json.encode({ content = 'println!("local");' })
      end

      return 404, vim.json.encode({ error = "not found" })
    end, function(server)
      local resolved = config.resolve({
        provider = "llamacpp",
        endpoint = server.url,
      })
      local result = perform(function(callback)
        return providers.complete({ prefix = "fn main() {", suffix = "}" }, resolved, callback)
      end)
      local received = vim.json.decode(server.requests[1].body)

      t.assert_equal(result.ok, true)
      t.assert_equal(result.provider, "llamacpp")
      t.assert_equal(result.text, 'println!("local");')
      t.assert_equal(server.requests[1].path, "/infill")
      t.assert_equal(received.input_prefix, "fn main() {")
      t.assert_equal(received.input_suffix, "}")
    end)
  end)

  t.test("Ollama health reports whether the configured model is present", function()
    with_server(function(request)
      if request.path == "/api/tags" then
        return 200,
          vim.json.encode({
            models = {
              { name = "qwen2.5-coder:7b" },
            },
          })
      end

      return 404, vim.json.encode({ error = "not found" })
    end, function(server)
      local resolved = config.resolve({
        provider = "ollama",
        endpoint = server.url,
        model = "qwen2.5-coder:7b",
      })
      local result = perform(function(callback)
        return providers.health(resolved, callback)
      end)

      t.assert_equal(result.ok, true)
      t.assert_equal(result.ready, true)
      t.assert_equal(result.model_available, true)
      t.assert_equal(result.provider, "ollama")
    end)
  end)

  t.test("provider schema failures return structured errors", function()
    with_server(function()
      return 200, vim.json.encode({ done = true })
    end, function(server)
      local resolved = config.resolve({
        provider = "ollama",
        endpoint = server.url,
        model = "local-coder",
      })
      local result = perform(function(callback)
        return providers.complete({ prefix = "before", suffix = "after" }, resolved, callback)
      end)

      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "provider")
      assert(result.error.message:find("completion text", 1, true), result.error.message)
    end)
  end)

  t.test("Ollama reports a missing model before starting HTTP", function()
    local resolved = config.resolve({ provider = "ollama" })
    local result, request = perform(function(callback)
      return providers.complete({ prefix = "before", suffix = "after" }, resolved, callback)
    end)

    t.assert_equal(result.ok, false)
    t.assert_equal(result.error.kind, "provider")
    assert(result.error.message:find("model must be configured", 1, true), result.error.message)
    t.assert_equal(request:is_done(), true)
  end)
end
