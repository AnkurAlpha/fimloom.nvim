return function(t)
  local commands = require("fimloom.commands")

  t.test("the plugin registers one idempotent FIMLoom command", function()
    t.assert_equal(vim.fn.exists(":FIMLoom"), 2)
    local registered, reason = commands.setup()
    t.assert_equal(registered, false)
    t.assert_equal(reason, "already registered")
  end)

  t.test("subcommand completion is deterministic and prefix filtered", function()
    t.assert_deep_equal(commands.complete("st"), { "start", "status", "stop" })
    t.assert_deep_equal(commands.complete("DIS"), { "disable", "dismiss" })
    t.assert_deep_equal(commands.complete("missing"), {})
  end)

  t.test("all public subcommands dispatch and report concise results", function()
    local notifications = {}
    local calls = {}
    local configured = false
    local enabled = false
    local fake = {}

    function fake.is_configured()
      return configured
    end

    function fake.is_enabled()
      return enabled
    end

    function fake.enable()
      calls.enable = (calls.enable or 0) + 1
      enabled = true
    end

    function fake.disable()
      calls.disable = (calls.disable or 0) + 1
      enabled = false
    end

    function fake.toggle()
      calls.toggle = (calls.toggle or 0) + 1
      enabled = not enabled
      return enabled
    end

    function fake.complete()
      calls.complete = (calls.complete or 0) + 1
      return true
    end

    function fake.accept()
      calls.accept = (calls.accept or 0) + 1
      return true
    end

    function fake.dismiss()
      calls.dismiss = (calls.dismiss or 0) + 1
      return true
    end

    function fake.start()
      calls.start = (calls.start or 0) + 1
      return true
    end

    function fake.stop()
      calls.stop = (calls.stop or 0) + 1
      return true
    end

    function fake.status()
      calls.status = (calls.status or 0) + 1
      return {
        configured = configured,
        enabled = enabled,
        provider = "llamacpp",
        endpoint = "http://127.0.0.1:8012",
        model = "/models/code.gguf",
        server = {
          status = "ready",
          owned = true,
        },
      }
    end

    local fake_log = {}
    function fake_log.notify(key, message, level, options)
      notifications[#notifications + 1] = {
        key = key,
        message = message,
        level = level,
        force = options.force,
      }
      return true
    end

    commands.setup({ api = fake, log = fake_log })
    local ok, error_message = xpcall(function()
      local successful, message = commands.execute("enable")
      t.assert_equal(successful, false)
      assert(message:find("setup", 1, true), message)

      configured = true
      t.assert_equal(commands.execute("enable"), true)
      t.assert_equal(enabled, true)
      t.assert_equal(commands.execute("toggle"), true)
      t.assert_equal(enabled, false)

      enabled = true
      t.assert_equal(commands.execute("disable"), true)
      t.assert_equal(enabled, false)
      t.assert_equal(commands.execute("complete"), true)
      t.assert_equal(commands.execute("accept"), true)
      t.assert_equal(commands.execute("dismiss"), true)
      t.assert_equal(commands.execute("start"), true)
      t.assert_equal(commands.execute("stop"), true)
      t.assert_equal(commands.execute("status"), true)

      local before_command = #notifications
      vim.cmd("FIMLoom status")
      t.assert_equal(#notifications, before_command + 1)
      local status_message = notifications[#notifications].message
      assert(status_message:find("provider=llamacpp", 1, true), status_message)
      assert(not status_message:find("stdout", 1, true), status_message)

      local unknown, unknown_message = commands.execute("missing")
      t.assert_equal(unknown, false)
      assert(unknown_message:find("Unknown", 1, true), unknown_message)
      t.assert_equal(notifications[#notifications].level, "error")

      for _, name in ipairs({
        "enable",
        "disable",
        "toggle",
        "complete",
        "accept",
        "dismiss",
        "start",
        "stop",
        "status",
      }) do
        assert(calls[name] and calls[name] > 0, name .. " was not dispatched")
      end
      for _, notification in ipairs(notifications) do
        t.assert_equal(notification.force, true)
      end
    end, debug.traceback)
    commands.setup()
    if not ok then
      error(error_message)
    end
  end)
end
