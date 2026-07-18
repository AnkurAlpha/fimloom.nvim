return function(t)
  local config = require("fimloom.config")
  local log = require("fimloom.log")
  local process = require("fimloom.process")
  local state = require("fimloom.state")

  local function health_sequence(results)
    local fake = {
      calls = 0,
    }

    function fake.health(_, callback)
      fake.calls = fake.calls + 1
      local index = math.min(fake.calls, #results)
      local result = vim.deepcopy(results[index])
      local request = {
        cancelled = false,
        done = false,
      }

      function request:cancel()
        if self.done then
          return false
        end
        self.cancelled = true
        self.done = true
        return true
      end

      function request:is_done()
        return self.done
      end

      vim.schedule(function()
        if request.cancelled then
          return
        end
        request.done = true
        callback(result)
      end)
      return request
    end

    return fake
  end

  local function resolved(server)
    return config.resolve({
      provider = "llamacpp",
      endpoint = "http://127.0.0.1:1",
      transport = {
        connect_timeout_ms = 50,
        request_timeout_ms = 100,
      },
      server = vim.tbl_deep_extend("force", {
        auto_start = true,
        auto_stop = true,
        command = { "local-server", "--serve" },
        startup_timeout_ms = 1000,
        startup_poll_interval_ms = 10,
      }, server or {}),
    })
  end

  local function wait_for_status(expected, timeout)
    local completed = vim.wait(timeout or 2000, function()
      return process.status().status == expected
    end, 5)
    assert(
      completed,
      string.format("server never reached %s: %s", expected, vim.inspect(process.status()))
    )
    return process.status()
  end

  local function with_runtime(callback)
    process.shutdown()
    log.shutdown()
    state._reset()
    local ok, error_message = xpcall(callback, debug.traceback)
    process.shutdown()
    log.shutdown()
    state._reset()
    if not ok then
      error(error_message)
    end
  end

  t.test("pre-existing healthy servers are ready but never owned or stopped", function()
    with_runtime(function()
      local starts = 0
      local stops = 0
      local provider = health_sequence({ { ok = true, ready = true } })
      local settings = resolved()
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function()
          starts = starts + 1
          return 31
        end,
        jobstop = function()
          stops = stops + 1
          return 1
        end,
      })

      local status = wait_for_status("ready")
      t.assert_equal(status.owned, false)
      t.assert_equal(status.job_id, nil)
      t.assert_equal(starts, 0)

      process.stop()
      t.assert_equal(stops, 0)
    end)
  end)

  t.test("configured argv starts, captures bounded output, and stops once", function()
    with_runtime(function()
      local captured_command
      local captured_options
      local stops = 0
      local provider = health_sequence({
        { ok = false, error = { message = "connection refused" } },
        { ok = true, ready = true },
      })
      local settings = resolved()
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function(command, options)
          captured_command = vim.deepcopy(command)
          captured_options = options
          vim.schedule(function()
            options.on_stdout(41, { string.rep("x", 70 * 1024) .. "STDOUT-END" })
            options.on_stderr(41, { "diagnostic stderr" })
          end)
          return 41
        end,
        jobstop = function(job)
          t.assert_equal(job, 41)
          stops = stops + 1
          return 1
        end,
        jobpid = function()
          return 4241
        end,
      })

      local status = wait_for_status("ready")
      t.assert_deep_equal(captured_command, { "local-server", "--serve" })
      t.assert_equal(captured_options.stdin, "null")
      t.assert_equal(captured_options.detach, false)
      t.assert_equal(status.owned, true)
      t.assert_equal(status.job_id, 41)
      t.assert_equal(status.pid, 4241)
      assert(#status.stdout_tail <= 64 * 1024, "stdout diagnostics were not bounded")
      assert(status.stdout_tail:find("STDOUT%-END$"), "stdout tail lost its newest output")
      assert(status.stderr_tail:find("diagnostic stderr", 1, true), "stderr was not captured")

      t.assert_equal(process.stop(), true)
      t.assert_equal(process.stop(), false)
      t.assert_equal(stops, 1)
      t.assert_equal(process.status().status, "stopped")
    end)
  end)

  t.test("a real child Neovim job is terminated by managed shutdown", function()
    with_runtime(function()
      local provider = health_sequence({
        { ok = false, error = { message = "connection refused" } },
        { ok = true, ready = true },
      })
      local script = vim.g.fimloom_test_root .. "/tests/fixtures/managed_process.lua"
      local settings = resolved({
        command = {
          vim.v.progpath,
          "--headless",
          "--clean",
          "-u",
          "NONE",
          "-l",
          script,
        },
      })
      state.configure(settings)
      process.setup(settings, { providers = provider })

      local status = wait_for_status("ready", 3000)
      local managed_job = status.job_id
      t.assert_equal(status.owned, true)
      t.assert_equal(vim.fn.jobwait({ managed_job }, 0)[1], -1)

      process.stop()
      local exited = vim.wait(3000, function()
        return vim.fn.jobwait({ managed_job }, 0)[1] ~= -1
      end, 10)
      assert(exited, "managed child Neovim did not exit after jobstop")
      t.assert_equal(process.status().owned, false)
    end)
  end)

  t.test("readiness timeout fails cleanly and terminates the owned job", function()
    with_runtime(function()
      local stops = 0
      local provider = health_sequence({
        { ok = false, error = { message = "not ready" } },
      })
      local settings = resolved({
        startup_timeout_ms = 40,
        startup_poll_interval_ms = 10,
      })
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function()
          return 51
        end,
        jobstop = function(job)
          t.assert_equal(job, 51)
          stops = stops + 1
          return 1
        end,
        jobpid = function()
          return 5151
        end,
      })

      local status = wait_for_status("failed")
      t.assert_equal(status.owned, false)
      t.assert_equal(status.error.kind, "startup_timeout")
      assert(status.error.message:find("40 ms", 1, true), status.error.message)
      t.assert_equal(stops, 1)
    end)
  end)

  t.test("an early managed process exit cancels readiness polling", function()
    with_runtime(function()
      local provider = health_sequence({
        { ok = false, error = { message = "not ready" } },
      })
      local settings = resolved()
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function(_, options)
          vim.schedule(function()
            options.on_exit(61, 17)
          end)
          return 61
        end,
        jobstop = function()
          error("an already-exited process must not be stopped")
        end,
        jobpid = function()
          return 6161
        end,
      })

      local status = wait_for_status("failed")
      t.assert_equal(status.owned, false)
      t.assert_equal(status.exit_code, 17)
      t.assert_equal(status.error.kind, "process_exit")
    end)
  end)

  t.test("startup command functions are resolved and validated at runtime", function()
    with_runtime(function()
      local starts = 0
      local provider = health_sequence({
        { ok = false, error = { message = "not ready" } },
      })
      local settings = resolved({
        command = function(received)
          received.provider = "changed"
          return "local-server --serve"
        end,
      })
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function()
          starts = starts + 1
          return 71
        end,
      })

      local status = wait_for_status("failed")
      t.assert_equal(status.error.kind, "command")
      assert(status.error.message:find("argument list", 1, true), status.error.message)
      t.assert_equal(starts, 0)
      t.assert_equal(state.get_config().provider, "llamacpp")
    end)
  end)

  t.test("VimLeavePre stops owned jobs only when auto-stop is enabled", function()
    with_runtime(function()
      local stops = 0
      local provider = health_sequence({
        { ok = false, error = { message = "not ready" } },
        { ok = true, ready = true },
      })
      local settings = resolved()
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function(_, options)
          t.assert_equal(options.detach, false)
          return 81
        end,
        jobstop = function(job)
          t.assert_equal(job, 81)
          stops = stops + 1
          return 1
        end,
        jobpid = function()
          return 8181
        end,
      })

      wait_for_status("ready")
      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      t.assert_equal(stops, 1)
      t.assert_equal(process.status().status, "stopped")
    end)

    with_runtime(function()
      local stops = 0
      local provider = health_sequence({
        { ok = false, error = { message = "not ready" } },
        { ok = true, ready = true },
      })
      local settings = resolved({ auto_stop = false })
      state.configure(settings)
      process.setup(settings, {
        providers = provider,
        jobstart = function(_, options)
          t.assert_equal(options.detach, true)
          return 82
        end,
        jobstop = function(job)
          t.assert_equal(job, 82)
          stops = stops + 1
          return 1
        end,
        jobpid = function()
          return 8282
        end,
      })

      wait_for_status("ready")
      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      t.assert_equal(stops, 0)
      t.assert_equal(process.status().owned, true)

      process.shutdown()
      t.assert_equal(stops, 1)
    end)
  end)
end
