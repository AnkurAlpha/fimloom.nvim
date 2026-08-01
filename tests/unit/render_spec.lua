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

  t.test("matching typed text consumes only the visible prefix", function()
    with_buffer({ "" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, 0 })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, 'print("Hello")'))

      vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "pri" })
      vim.api.nvim_win_set_cursor(window, { 1, 3 })
      local status, inserted = render.consume_matching_prefix()
      t.assert_equal(status, "consumed")
      t.assert_equal(inserted, "pri")
      t.assert_equal(render.get().text, 'nt("Hello")')
      t.assert_equal(render.get().column, 3)

      t.assert_equal(render.accept(), true)
      t.assert_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1], 'print("Hello")')
    end)
  end)

  t.test("full manual typing clears the suggestion without inserting twice", function()
    with_buffer({ "value = " }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, "42"))

      vim.api.nvim_buf_set_text(buffer, 0, #"value = ", 0, #"value = ", { "42" })
      vim.api.nvim_win_set_cursor(window, { 1, #"value = 42" })
      t.assert_equal(render.consume_matching_prefix(), "complete")
      t.assert_equal(render.has_suggestion(), false)
      t.assert_equal(render.accept(), false)
      t.assert_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1], "value = 42")
    end)
  end)

  t.test("matching-prefix consumption uses Neovim UTF-8 byte columns safely", function()
    with_buffer({ "" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, 0 })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, "αβγ"))

      vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "αβ" })
      vim.api.nvim_win_set_cursor(window, { 1, #"αβ" })
      t.assert_equal(render.consume_matching_prefix(), "consumed")
      t.assert_equal(render.get().text, "γ")
      t.assert_equal(render.accept(), true)
      t.assert_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1], "αβγ")
    end)
  end)

  t.test("mismatches, cursor movement, and backspace invalidate a suggestion", function()
    with_buffer({ "pri" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, 3 })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, 'nt("ok")'))

      vim.api.nvim_buf_set_text(buffer, 0, 3, 0, 3, { "x" })
      vim.api.nvim_win_set_cursor(window, { 1, 4 })
      t.assert_equal(render.consume_matching_prefix(), "diverged")
      t.assert_equal(render.has_suggestion(), false)

      local next_context = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(next_context, "more"))
      vim.api.nvim_win_set_cursor(window, { 1, 2 })
      t.assert_equal(render.consume_matching_prefix(), "diverged")

      vim.api.nvim_win_set_cursor(window, { 1, 4 })
      local final_context = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(final_context, "more"))
      vim.api.nvim_buf_set_text(buffer, 0, 3, 0, 4, { "" })
      vim.api.nvim_win_set_cursor(window, { 1, 3 })
      t.assert_equal(render.consume_matching_prefix(), "diverged")
    end)
  end)

  t.test("multiline paste including newline and indentation is consumed", function()
    with_buffer({ "if ready then" }, function(buffer, window)
      local column = #"if ready then"
      vim.api.nvim_win_set_cursor(window, { 1, column })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, "\n  run()\nend"))

      vim.api.nvim_buf_set_text(buffer, 0, column, 0, column, { "", "  run()" })
      vim.api.nvim_win_set_cursor(window, { 2, #"  run()" })
      t.assert_equal(render.consume_matching_prefix(), "consumed")
      t.assert_equal(render.get().text, "\nend")

      t.assert_equal(render.accept(), true)
      t.assert_deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), {
        "if ready then",
        "  run()",
        "end",
      })
    end)
  end)

  t.test("unrelated buffer edits and buffer switches invalidate suggestion state", function()
    with_buffer({ "value = ", "other" }, function(buffer, window)
      vim.api.nvim_win_set_cursor(window, { 1, #"value = " })
      local captured = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(captured, "42"))
      vim.api.nvim_buf_set_text(buffer, 1, 0, 1, 0, { "changed " })
      t.assert_equal(render.consume_matching_prefix(), "diverged")

      local second = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_win_set_buf(window, buffer)
      local next_context = assert(context.capture(config.resolve(), buffer, window))
      assert(render.show(next_context, "42"))
      vim.api.nvim_win_set_buf(window, second)
      t.assert_equal(render.consume_matching_prefix(), "diverged")
      vim.api.nvim_win_set_buf(window, buffer)
      vim.api.nvim_buf_delete(second, { force = true })
    end)
  end)

  t.test("suggestion highlight supports defaults, colors, links, and manual precedence", function()
    local group = render.highlight_group()
    vim.api.nvim_set_hl(0, group, {})
    render.setup(config.resolve())
    local default_hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    t.assert_equal(default_hl.fg, 0x808080)
    t.assert_equal(default_hl.ctermfg, 244)

    vim.api.nvim_set_hl(0, group, {})
    render.setup(config.resolve({
      ui = {
        suggestion = {
          fg = "#707070",
          ctermfg = 242,
          italic = true,
        },
      },
    }))
    local configured = vim.api.nvim_get_hl(0, { name = group, link = false })
    t.assert_equal(configured.fg, 0x707070)
    t.assert_equal(configured.ctermfg, 242)
    t.assert_equal(configured.italic, true)

    vim.api.nvim_set_hl(0, group, {})
    render.setup(config.resolve({ ui = { suggestion_hl = "NonText" } }))
    local linked = vim.api.nvim_get_hl(0, { name = group, link = true })
    t.assert_equal(linked.link, "NonText")

    vim.api.nvim_set_hl(0, group, { fg = "#123456", italic = true })
    render.setup(config.resolve())
    local manual = vim.api.nvim_get_hl(0, { name = group, link = false })
    t.assert_equal(manual.fg, 0x123456)
    t.assert_equal(manual.italic, true)
  end)

  t.test("colorscheme changes restore a cleared configured highlight", function()
    local group = render.highlight_group()
    vim.api.nvim_set_hl(0, group, {})
    render.setup(config.resolve({ ui = { suggestion_hl = "Comment" } }))
    local configured = vim.api.nvim_get_hl(0, { name = group, link = true })
    t.assert_equal(configured.link, "Comment")

    vim.api.nvim_set_hl(0, group, {})
    vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "fimloom-test" })
    local restored = vim.api.nvim_get_hl(0, { name = group, link = true })
    t.assert_equal(restored.link, "Comment")
  end)

  t.test("colorscheme changes preserve a user-defined suggestion highlight", function()
    local group = render.highlight_group()
    vim.api.nvim_set_hl(0, group, {})
    render.setup(config.resolve({ ui = { suggestion_hl = "Comment" } }))

    vim.api.nvim_set_hl(0, group, { fg = "#123456", italic = true })
    vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "fimloom-test" })
    local manual = vim.api.nvim_get_hl(0, { name = group, link = false })
    t.assert_equal(manual.fg, 0x123456)
    t.assert_equal(manual.italic, true)
  end)
end
