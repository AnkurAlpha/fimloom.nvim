return function(t)
  local config = require("fimloom.config")
  local context = require("fimloom.context")

  local function with_buffer(lines, callback)
    local previous = vim.api.nvim_get_current_buf()
    local buffer = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    local window = vim.api.nvim_get_current_win()
    local previous_virtualedit = vim.wo[window].virtualedit
    vim.wo[window].virtualedit = "onemore"

    local ok, error_message = xpcall(function()
      callback(buffer, window)
    end, debug.traceback)

    vim.wo[window].virtualedit = previous_virtualedit
    if vim.api.nvim_buf_is_valid(previous) then
      vim.api.nvim_set_current_buf(previous)
    end
    vim.api.nvim_buf_delete(buffer, { force = true })

    if not ok then
      error(error_message)
    end
  end

  t.test("context captures cursor metadata and bounded FIM text", function()
    with_buffer(
      { "local first = 1", "  local answer = 4", "return answer" },
      function(buffer, window)
        vim.bo[buffer].filetype = "lua"
        vim.api.nvim_win_set_cursor(window, { 2, #"  local answer = " })

        local captured = assert(context.capture(config.resolve(), buffer, window))

        t.assert_equal(captured.bufnr, buffer)
        t.assert_equal(captured.winid, window)
        t.assert_equal(captured.filetype, "lua")
        t.assert_equal(captured.row, 2)
        t.assert_equal(captured.column, #"  local answer = ")
        t.assert_equal(captured.prefix, "local first = 1\n  local answer = ")
        t.assert_equal(captured.suffix, "4\nreturn answer")
        t.assert_equal(captured.indentation, "  ")
        t.assert_equal(captured.changedtick, vim.api.nvim_buf_get_changedtick(buffer))
      end
    )
  end)

  t.test("context byte limits preserve UTF-8 boundaries", function()
    with_buffer({ "αβγXYZ" }, function(buffer, window)
      local prefix_config = config.resolve({
        completion = {
          context = {
            max_prefix_bytes = 5,
            max_suffix_bytes = 0,
          },
        },
      })
      vim.api.nvim_win_set_cursor(window, { 1, #"αβγXYZ" })
      local prefix = assert(context.capture(prefix_config, buffer, window))

      t.assert_equal(prefix.prefix, "γXYZ")
      t.assert_equal(vim.fn.strchars(prefix.prefix), 4)

      local suffix_config = config.resolve({
        completion = {
          context = {
            max_prefix_bytes = 0,
            max_suffix_bytes = 5,
          },
        },
      })
      vim.api.nvim_win_set_cursor(window, { 1, 0 })
      local suffix = assert(context.capture(suffix_config, buffer, window))

      t.assert_equal(suffix.suffix, "αβ")
      t.assert_equal(vim.fn.strchars(suffix.suffix), 2)
    end)
  end)

  t.test("context honors filetype allow and deny lists", function()
    with_buffer({ "local value = 1" }, function(buffer, window)
      vim.bo[buffer].filetype = "lua"
      local denied, denied_reason = context.capture(
        config.resolve({
          completion = {
            context = {
              filetypes = {
                deny = { "lua" },
              },
            },
          },
        }),
        buffer,
        window
      )
      local not_allowed, allow_reason = context.capture(
        config.resolve({
          completion = {
            context = {
              filetypes = {
                allow = { "rust" },
              },
            },
          },
        }),
        buffer,
        window
      )

      t.assert_equal(denied, nil)
      assert(denied_reason:find("filetype", 1, true), denied_reason)
      t.assert_equal(not_allowed, nil)
      assert(allow_reason:find("filetype", 1, true), allow_reason)
    end)
  end)

  t.test("context rejects unsuitable special buffers", function()
    with_buffer({ "prompt" }, function(buffer, window)
      vim.bo[buffer].buftype = "prompt"
      local captured, reason = context.capture(config.resolve(), buffer, window)

      t.assert_equal(captured, nil)
      assert(reason:find("buffer type", 1, true), reason)
    end)
  end)

  t.test("captured context becomes stale after cursor or buffer changes", function()
    with_buffer({ "local answer = " }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"local answer = " })
      local captured = assert(context.capture(config.resolve(), buffer, window))

      t.assert_equal(context.is_current(captured), true)
      vim.api.nvim_win_set_cursor(window, { 1, 0 })
      t.assert_equal(context.is_current(captured), false)

      vim.api.nvim_win_set_cursor(window, { 1, captured.column })
      vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "x" })
      t.assert_equal(context.is_current(captured), false)
    end)
  end)
end
