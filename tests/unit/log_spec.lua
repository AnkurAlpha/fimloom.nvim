return function(t)
  local config = require("fimloom.config")
  local log = require("fimloom.log")

  local function settings(options)
    return config.resolve({
      log = vim.tbl_deep_extend("force", {
        level = "debug",
        file = false,
        max_entries = 3,
        notify = true,
        notify_cooldown_ms = 100,
      }, options or {}),
    })
  end

  t.test("diagnostic entries are bounded and redact source-bearing fields", function()
    log.shutdown()
    log.setup(settings(), {
      timestamp = function()
        return "2026-07-18T00:00:00Z"
      end,
    })

    log.write("error", "provider_failure", {
      provider = "ollama",
      prefix = "SECRET PREFIX",
      nested = {
        suffix = "SECRET SUFFIX",
        response = "SECRET RESPONSE",
      },
    })
    local serialized = vim.inspect(log.entries())
    assert(not serialized:find("SECRET", 1, true), serialized)
    assert(serialized:find("<redacted>", 1, true), serialized)

    log.write("info", "second", { status = "ready" })
    log.write("warn", "third", { kind = "timeout" })
    log.write("debug", "fourth", { bytes = 10 })
    local entries = log.entries()
    t.assert_equal(#entries, 3)
    t.assert_equal(entries[1].event, "second")
    t.assert_equal(entries[3].event, "fourth")
    log.shutdown()
  end)

  t.test("automatic diagnostic notifications are rate-limited by failure key", function()
    local now = 1000
    local notifications = {}
    log.shutdown()
    log.setup(settings(), {
      now_ms = function()
        return now
      end,
      notify = function(message, level, options)
        notifications[#notifications + 1] = {
          message = message,
          level = level,
          title = options.title,
        }
      end,
    })

    t.assert_equal(log.notify("completion:timeout", "timed out", "warn"), true)
    t.assert_equal(log.notify("completion:timeout", "timed out again", "warn"), false)
    t.assert_equal(#notifications, 1)

    now = 1100
    t.assert_equal(log.notify("completion:timeout", "timed out later", "warn"), true)
    t.assert_equal(
      log.notify("completion:timeout", "manual retry failed", "warn", { force = true }),
      true
    )
    t.assert_equal(#notifications, 3)
    t.assert_equal(notifications[1].title, "FIMLoom")
    log.shutdown()
  end)

  t.test("optional JSONL persistence rotates within its configured byte bound", function()
    local writes = {}
    log.shutdown()
    log.setup(
      settings({
        file = "/tmp/fimloom-test.log",
        max_file_bytes = 1024,
      }),
      {
        expand = function(path)
          return path
        end,
        mkdir = function()
          return 1
        end,
        file_size = function()
          return 1000
        end,
        write_lines = function(path, lines, append)
          writes[#writes + 1] = {
            path = path,
            lines = vim.deepcopy(lines),
            append = append,
          }
          return 0
        end,
      }
    )

    log.write("error", "provider_failure", {
      prompt = "PRIVATE SOURCE",
      kind = "connection",
    })
    t.assert_equal(#writes, 1)
    t.assert_equal(writes[1].path, "/tmp/fimloom-test.log")
    t.assert_equal(writes[1].append, false)
    local serialized = table.concat(writes[1].lines, "\n")
    assert(not serialized:find("PRIVATE SOURCE", 1, true), serialized)
    assert(#serialized <= 1024, "rotated diagnostics exceeded the configured bound")
    t.assert_equal(log.status().file_error, nil)
    log.shutdown()
  end)
end
