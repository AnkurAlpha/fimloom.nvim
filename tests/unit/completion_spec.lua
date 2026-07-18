return function(t)
  local completion = require("fimloom.completion")
  local config = require("fimloom.config")
  local log = require("fimloom.log")
  local render = require("fimloom.render")
  local state = require("fimloom.state")

  local function fake_provider()
    local fake = {
      calls = {},
    }

    function fake.complete(captured, _, callback)
      local handle = {
        cancelled = false,
      }

      function handle:cancel()
        self.cancelled = true
        return true
      end

      fake.calls[#fake.calls + 1] = {
        context = captured,
        callback = callback,
        handle = handle,
      }
      return handle
    end

    return fake
  end

  local function with_runtime(options, lines, callback)
    completion.shutdown()
    log.shutdown()
    render.clear()
    state._reset()

    local previous = vim.api.nvim_get_current_buf()
    local buffer = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    local window = vim.api.nvim_get_current_win()
    local previous_virtualedit = vim.wo[window].virtualedit
    vim.wo[window].virtualedit = "onemore"
    local resolved = config.resolve(vim.tbl_deep_extend("force", {
      provider = "llamacpp",
      keymaps = {
        accept = false,
        dismiss = false,
        manual = false,
      },
    }, options or {}))
    local fake = fake_provider()
    state.configure(resolved)
    completion.setup(resolved, { providers = fake })

    local ok, error_message = xpcall(function()
      callback(buffer, window, fake, resolved)
    end, debug.traceback)

    completion.shutdown()
    log.shutdown()
    render.clear()
    vim.wo[window].virtualedit = previous_virtualedit
    if vim.api.nvim_buf_is_valid(previous) then
      vim.api.nvim_set_current_buf(previous)
    end
    vim.api.nvim_buf_delete(buffer, { force = true })
    state._reset()

    if not ok then
      error(error_message)
    end
  end

  local function wait_for(predicate, message)
    local completed = vim.wait(1000, predicate, 5)
    assert(completed, message or "scheduled completion work did not finish")
  end

  t.test("manual completion renders and accepts provider text", function()
    with_runtime({}, { "local answer = " }, function(buffer, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"local answer = " })

      t.assert_equal(completion.trigger({ manual = true }), true)
      t.assert_equal(#fake.calls, 1)
      fake.calls[1].callback({ ok = true, text = "42" })
      wait_for(render.has_suggestion)

      t.assert_equal(render.get().text, "42")
      t.assert_equal(completion.accept(), true)
      t.assert_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1], "local answer = 42")
    end)
  end)

  t.test("new completion requests cancel and supersede older work", function()
    with_runtime({}, { "value = " }, function(_, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      assert(completion.trigger({ manual = true }))
      assert(completion.trigger({ manual = true }))

      t.assert_equal(#fake.calls, 2)
      t.assert_equal(fake.calls[1].handle.cancelled, true)
      fake.calls[1].callback({ ok = true, text = "old" })
      fake.calls[2].callback({ ok = true, text = "new" })
      wait_for(render.has_suggestion)

      t.assert_equal(render.get().text, "new")
    end)
  end)

  t.test("stale responses never render after the buffer changes", function()
    with_runtime({}, { "value = " }, function(buffer, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      assert(completion.trigger({ manual = true }))
      vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "local " })
      fake.calls[1].callback({ ok = true, text = "1" })
      vim.wait(50, function()
        return false
      end, 5)

      t.assert_equal(render.has_suggestion(), false)
      t.assert_equal(completion.status().active_request_id, nil)
    end)
  end)

  t.test("automatic completion is debounced without blocking text changes", function()
    with_runtime({
      completion = {
        debounce_ms = 25,
      },
    }, { "value = " }, function(_, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })

      t.assert_equal(completion._on_text_changed(), true)
      t.assert_equal(#fake.calls, 0)
      t.assert_equal(completion.status().debounce_pending, true)
      wait_for(function()
        return #fake.calls == 1
      end, "debounced provider request was not started")
      t.assert_equal(completion.status().debounce_pending, false)
    end)
  end)

  t.test("typing cancels an active request before scheduling its replacement", function()
    with_runtime({
      completion = {
        debounce_ms = 20,
      },
    }, { "value = " }, function(_, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      assert(completion.trigger({ manual = true }))
      local first = fake.calls[1]

      assert(completion._on_text_changed())
      t.assert_equal(first.handle.cancelled, true)
      t.assert_equal(#fake.calls, 1)
      wait_for(function()
        return #fake.calls == 2
      end)
    end)
  end)

  t.test("completion cleanup normalizes fences and removes suffix overlap", function()
    t.assert_equal(completion.sanitize("```lua\r\nvalue\r\nend\r\n```", ""), "value\nend")
    t.assert_equal(completion.sanitize("valueend", "end\nnext"), "value")
    t.assert_equal(completion.sanitize("end", "end\nnext"), nil)
    t.assert_equal(completion.sanitize("  \n", ""), nil)
    t.assert_equal(
      completion.sanitize("one\ntwo\nthree", "", {
        max_bytes = 100,
        max_lines = 2,
      }),
      "one\ntwo"
    )
    t.assert_equal(
      completion.sanitize("αβγ", "", {
        max_bytes = 5,
        max_lines = 10,
      }),
      "αβ"
    )
  end)

  t.test("dismissal cancels pending work and is idempotent", function()
    with_runtime({}, { "value = " }, function(_, window, fake)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      assert(completion.trigger({ manual = true }))

      t.assert_equal(completion.dismiss(), true)
      t.assert_equal(fake.calls[1].handle.cancelled, true)
      t.assert_equal(completion.dismiss(), false)
      t.assert_equal(completion.status().active_request_id, nil)
    end)
  end)

  t.test("setup preserves existing insert-mode mappings", function()
    completion.shutdown()
    state._reset()
    vim.keymap.set("i", "<Tab>", "existing-tab-map", {
      desc = "Existing tab mapping",
    })

    local ok, error_message = xpcall(function()
      local resolved = config.resolve({
        provider = "llamacpp",
      })
      state.configure(resolved)
      completion.setup(resolved, { providers = fake_provider() })
      local existing = vim.fn.maparg("<Tab>", "i", false, true)

      t.assert_equal(existing.desc, "Existing tab mapping")
      t.assert_equal(existing.rhs, "existing-tab-map")
    end, debug.traceback)

    completion.shutdown()
    pcall(vim.keymap.del, "i", "<Tab>")
    state._reset()

    if not ok then
      error(error_message)
    end
  end)
end
