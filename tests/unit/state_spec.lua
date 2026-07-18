return function(t)
  local state = require("fimloom.state")

  t.test("runtime state stores defensive configuration copies", function()
    local resolved = {
      enabled = true,
      nested = { value = 1 },
    }

    state._reset()
    state.configure(resolved)
    resolved.nested.value = 2

    local first = state.get_config()
    t.assert_equal(first.nested.value, 1)

    first.nested.value = 3
    t.assert_equal(state.get_config().nested.value, 1)
  end)

  t.test("enabled state is explicit and type checked", function()
    state._reset()
    state.configure({ enabled = false })
    t.assert_equal(state.is_enabled(), false)

    state.set_enabled(true)
    t.assert_equal(state.is_enabled(), true)

    t.assert_error(function()
      state.set_enabled("yes")
    end, "expected a boolean")
  end)

  t.test("request identifiers increase monotonically", function()
    state._reset()

    t.assert_equal(state.next_request_id(), 1)
    t.assert_equal(state.next_request_id(), 2)
    t.assert_equal(state.snapshot().request_seq, 2)
  end)

  t.test("server lifecycle state is validated and copied", function()
    state._reset()
    local server = {
      status = "starting",
      owned = true,
      job_id = 12,
      started_command = { "ollama", "serve" },
      stdout_tail = "ready",
      stderr_tail = "",
    }
    state.set_server(server)
    server.started_command[1] = "changed"

    local stored = state.get_server()
    t.assert_equal(stored.started_command[1], "ollama")
    stored.status = "failed"
    t.assert_equal(state.get_server().status, "starting")

    t.assert_error(function()
      state.set_server({ status = "missing", owned = false })
    end, "unknown server status")
    t.assert_error(function()
      state.set_server({ status = "ready", owned = "yes" })
    end, "server.owned must be a boolean")
  end)
end
