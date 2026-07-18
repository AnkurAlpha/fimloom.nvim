return function(t)
  local config = require("fimloom.config")
  local context = require("fimloom.context")
  local render = require("fimloom.render")

  local function with_buffer(lines, callback)
    render.clear()
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

    render.clear()
    vim.wo[window].virtualedit = previous_virtualedit
    if vim.api.nvim_buf_is_valid(previous) then
      vim.api.nvim_set_current_buf(previous)
    end
    vim.api.nvim_buf_delete(buffer, { force = true })

    if not ok then
      error(error_message)
    end
  end

  t.test("renderer previews single-line text with an inline extmark", function()
    with_buffer({ "local answer = " }, function(buffer, window)
      render.setup()
      vim.api.nvim_win_set_cursor(window, { 1, #"local answer = " })
      local captured = assert(context.capture(config.resolve(), buffer, window))

      t.assert_equal(render.show(captured, "42"), true)
      local marks =
        vim.api.nvim_buf_get_extmarks(buffer, render.namespace(), 0, -1, { details = true })

      t.assert_equal(#marks, 1)
      t.assert_deep_equal(marks[1][4].virt_text, { { "42", "FIMLoomSuggestion" } })
      t.assert_equal(marks[1][4].virt_text_pos, "inline")
      t.assert_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1], "local answer = ")
    end)
  end)

  t.test("renderer previews continuation lines without editing the buffer", function()
    with_buffer({ "fn main() {" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"fn main() {" })
      local captured = assert(context.capture(config.resolve(), buffer, window))

      t.assert_equal(render.show(captured, "\n  return 0;\n}"), true)
      local marks =
        vim.api.nvim_buf_get_extmarks(buffer, render.namespace(), 0, -1, { details = true })

      t.assert_deep_equal(marks[1][4].virt_lines, {
        { { "  return 0;", "FIMLoomSuggestion" } },
        { { "}", "FIMLoomSuggestion" } },
      })
      t.assert_deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { "fn main() {" })
    end)
  end)

  t.test("accept inserts multiline text in one buffer edit and moves the cursor", function()
    with_buffer({ "fn main() {" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"fn main() {" })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, "\n  return 0;\n}"))

      t.assert_equal(render.accept(), true)
      t.assert_deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), {
        "fn main() {",
        "  return 0;",
        "}",
      })
      t.assert_deep_equal(vim.api.nvim_win_get_cursor(window), { 3, 1 })
      t.assert_equal(render.has_suggestion(), false)
    end)
  end)

  t.test("renderer refuses stale anchors and clears idempotently", function()
    with_buffer({ "value = " }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "local " })

      t.assert_equal(render.show(captured, "1"), false)
      t.assert_equal(render.clear(), false)
      t.assert_equal(render.accept(), false)
    end)
  end)
end
