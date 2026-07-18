local fixture = require("tests.fixtures.http_server")

return function(t)
  local transport = require("fimloom.transport")

  local function perform(options, wait_ms)
    local result
    local request = transport.request(options, function(response)
      result = response
    end)
    local completed = vim.wait(wait_ms or 3000, function()
      return result ~= nil
    end, 10)

    assert(completed, "transport callback did not complete before the test timeout")
    return result, request
  end

  local function with_server(callback)
    local server = fixture.start()
    local ok, error_message = xpcall(function()
      callback(server)
    end, debug.traceback)

    server.stop()
    if not ok then
      error(error_message)
    end
  end

  t.test("transport performs asynchronous GET requests", function()
    with_server(function(server)
      local result, request = perform({ url = server.url .. "/ok" })

      t.assert_equal(result.ok, true)
      t.assert_equal(result.status, 200)
      t.assert_equal(result.json.message, "ok")
      t.assert_equal(request:is_done(), true)
    end)
  end)

  t.test("transport JSON-encodes POST bodies", function()
    with_server(function(server)
      local result = perform({
        url = server.url .. "/echo",
        body = {
          model = "local-code-model",
          prompt = "local context",
        },
      })

      t.assert_equal(result.ok, true)
      t.assert_deep_equal(result.json, {
        model = "local-code-model",
        prompt = "local context",
      })
      t.assert_equal(server.requests[1].method, "POST")
      t.assert_equal(server.requests[1].headers["content-type"], "application/json")
    end)
  end)

  t.test("transport returns structured HTTP errors", function()
    with_server(function(server)
      local result = perform({ url = server.url .. "/error" })

      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "http")
      t.assert_equal(result.status, 503)
      t.assert_equal(result.json.error, "unavailable")
    end)
  end)

  t.test("transport distinguishes malformed JSON", function()
    with_server(function(server)
      local result = perform({ url = server.url .. "/bad-json" })

      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "decode")
      t.assert_equal(result.status, 200)
    end)
  end)

  t.test("transport enforces the response byte limit", function()
    with_server(function(server)
      local result = perform({
        url = server.url .. "/large",
        max_response_bytes = 512,
      })

      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "response_too_large")
    end)
  end)

  t.test("transport distinguishes request timeouts", function()
    with_server(function(server)
      local result = perform({
        url = server.url .. "/slow",
        connect_timeout_ms = 100,
        request_timeout_ms = 50,
      })

      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "timeout")
    end)
  end)

  t.test("transport cancellation terminates an active request", function()
    with_server(function(server)
      local result
      local request = transport.request({ url = server.url .. "/slow" }, function(response)
        result = response
      end)

      vim.defer_fn(function()
        request:cancel()
      end, 20)

      local completed = vim.wait(3000, function()
        return result ~= nil
      end, 10)

      assert(completed, "cancelled transport callback did not complete")
      t.assert_equal(result.ok, false)
      t.assert_equal(result.error.kind, "cancelled")
      t.assert_equal(request:is_done(), true)
      t.assert_equal(request:cancel(), false)
    end)
  end)

  t.test("transport distinguishes connection failures", function()
    local result = perform({
      url = "http://127.0.0.1:1/unavailable",
      connect_timeout_ms = 100,
      request_timeout_ms = 500,
    })

    t.assert_equal(result.ok, false)
    t.assert_equal(result.error.kind, "connection")
  end)
end
