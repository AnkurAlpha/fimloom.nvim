local M = {}

local namespace = vim.api.nvim_create_namespace("fimloom")
local highlight = "FIMLoomSuggestion"
local active
local highlight_augroup
local configured_ui

local function split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function delete_mark(suggestion)
  if suggestion and vim.api.nvim_buf_is_valid(suggestion.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, suggestion.bufnr, namespace, suggestion.mark_id)
  end
end

local function highlight_spec()
  if configured_ui and configured_ui.suggestion_hl then
    return {
      link = configured_ui.suggestion_hl,
    }
  end

  local suggestion = configured_ui and configured_ui.suggestion or {}
  return {
    fg = suggestion.fg or "#808080",
    ctermfg = suggestion.ctermfg or 244,
    italic = suggestion.italic == true,
  }
end

local function highlight_is_cleared()
  local ok, current = pcall(vim.api.nvim_get_hl, 0, { name = highlight, link = true })
  return not ok or next(current) == nil
end

local function apply_highlight()
  if not highlight_is_cleared() then
    return
  end

  vim.api.nvim_set_hl(0, highlight, highlight_spec())
end

local function mark_options(text)
  local lines = split_lines(text)
  local options = {
    virt_text = { { lines[1], highlight } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    priority = 200,
    right_gravity = false,
    undo_restore = false,
  }

  if #lines > 1 then
    options.virt_lines = {}
    for index = 2, #lines do
      options.virt_lines[#options.virt_lines + 1] = { { lines[index], highlight } }
    end
  end

  return options
end

local function place_mark(suggestion)
  suggestion.mark_id = vim.api.nvim_buf_set_extmark(
    suggestion.bufnr,
    namespace,
    suggestion.row - 1,
    suggestion.column,
    mark_options(suggestion.text)
  )
end

local function is_valid(suggestion)
  if not suggestion then
    return false
  end

  if not vim.api.nvim_buf_is_valid(suggestion.bufnr) then
    return false
  end

  if not vim.api.nvim_win_is_valid(suggestion.winid) then
    return false
  end

  if vim.api.nvim_win_get_buf(suggestion.winid) ~= suggestion.bufnr then
    return false
  end

  if vim.api.nvim_buf_get_changedtick(suggestion.bufnr) ~= suggestion.changedtick then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(suggestion.winid)
  return cursor[1] == suggestion.row and cursor[2] == suggestion.column
end

local function inserted_at_anchor(suggestion, cursor)
  if cursor[1] < suggestion.row then
    return nil
  end
  if cursor[1] == suggestion.row and cursor[2] <= suggestion.column then
    return nil
  end

  local added_rows = cursor[1] - suggestion.row
  if vim.api.nvim_buf_line_count(suggestion.bufnr) ~= suggestion.line_count + added_rows then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(suggestion.bufnr, suggestion.row - 1, cursor[1], false)
  if #lines ~= added_rows + 1 then
    return nil
  end

  local original_prefix = suggestion.anchor_line:sub(1, suggestion.column)
  local original_suffix = suggestion.anchor_line:sub(suggestion.column + 1)
  if lines[1]:sub(1, suggestion.column) ~= original_prefix then
    return nil
  end

  if #lines == 1 then
    if lines[1]:sub(cursor[2] + 1) ~= original_suffix then
      return nil
    end
    return lines[1]:sub(suggestion.column + 1, cursor[2])
  end

  if lines[#lines]:sub(cursor[2] + 1) ~= original_suffix then
    return nil
  end

  local inserted = { lines[1]:sub(suggestion.column + 1) }
  for index = 2, #lines - 1 do
    inserted[#inserted + 1] = lines[index]
  end
  inserted[#inserted + 1] = lines[#lines]:sub(1, cursor[2])
  return table.concat(inserted, "\n")
end

---Define and maintain the suggestion highlight without replacing an existing group.
---@param config? table
function M.setup(config)
  configured_ui = vim.deepcopy(config and config.ui or {})
  apply_highlight()

  highlight_augroup = vim.api.nvim_create_augroup("FIMLoomHighlight", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = highlight_augroup,
    callback = apply_highlight,
    desc = "Restore the FIMLoom suggestion highlight if a colorscheme clears it",
  })
end

---Remove the active suggestion, if any.
---@return boolean removed
function M.clear()
  if not active then
    return false
  end

  local suggestion = active
  active = nil
  delete_mark(suggestion)
  return true
end

---Render a suggestion at its captured cursor anchor.
---@param context table
---@param text string
---@return boolean rendered
function M.show(context, text)
  if type(context) ~= "table" then
    error("fimloom.render.show: context must be a table", 2)
  end

  if type(text) ~= "string" or not text:find("%S") then
    return false
  end

  M.clear()

  if
    not vim.api.nvim_buf_is_valid(context.bufnr) or not vim.api.nvim_win_is_valid(context.winid)
  then
    return false
  end

  if vim.api.nvim_win_get_buf(context.winid) ~= context.bufnr then
    return false
  end

  if vim.api.nvim_buf_get_changedtick(context.bufnr) ~= context.changedtick then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(context.winid)
  if cursor[1] ~= context.row or cursor[2] ~= context.column then
    return false
  end

  local anchor_line =
    vim.api.nvim_buf_get_lines(context.bufnr, context.row - 1, context.row, false)[1]
  active = {
    bufnr = context.bufnr,
    winid = context.winid,
    row = context.row,
    column = context.column,
    changedtick = context.changedtick,
    line_count = vim.api.nvim_buf_line_count(context.bufnr),
    anchor_line = anchor_line or "",
    text = text,
  }
  place_mark(active)
  return true
end

---Consume a verified insertion when it exactly matches the visible suggestion prefix.
---@return string status "none", "unchanged", "consumed", "complete", or "diverged"
---@return string? inserted
function M.consume_matching_prefix()
  if not active then
    return "none"
  end

  local suggestion = active
  if
    not vim.api.nvim_buf_is_valid(suggestion.bufnr)
    or not vim.api.nvim_win_is_valid(suggestion.winid)
    or vim.api.nvim_win_get_buf(suggestion.winid) ~= suggestion.bufnr
  then
    M.clear()
    return "diverged"
  end

  local cursor = vim.api.nvim_win_get_cursor(suggestion.winid)
  local changedtick = vim.api.nvim_buf_get_changedtick(suggestion.bufnr)
  if changedtick == suggestion.changedtick then
    if cursor[1] == suggestion.row and cursor[2] == suggestion.column then
      return "unchanged"
    end
    M.clear()
    return "diverged"
  end

  if changedtick ~= suggestion.changedtick + 1 then
    M.clear()
    return "diverged"
  end

  local inserted = inserted_at_anchor(suggestion, cursor)
  if not inserted or inserted == "" or suggestion.text:sub(1, #inserted) ~= inserted then
    M.clear()
    return "diverged", inserted
  end

  local remaining = suggestion.text:sub(#inserted + 1)
  if remaining == "" then
    M.clear()
    return "complete", inserted
  end

  delete_mark(suggestion)
  suggestion.row = cursor[1]
  suggestion.column = cursor[2]
  suggestion.changedtick = changedtick
  suggestion.line_count = vim.api.nvim_buf_line_count(suggestion.bufnr)
  suggestion.anchor_line = vim.api.nvim_buf_get_lines(
    suggestion.bufnr,
    cursor[1] - 1,
    cursor[1],
    false
  )[1] or ""
  suggestion.text = remaining
  place_mark(suggestion)
  return "consumed", inserted
end

---Return whether a suggestion is currently displayed.
---@return boolean
function M.has_suggestion()
  return active ~= nil
end

---Return whether the active suggestion still matches its editor anchor.
---@return boolean
function M.is_current()
  return is_valid(active)
end

---Return a defensive copy of active suggestion metadata.
---@return table?
function M.get()
  return active and vim.deepcopy(active) or nil
end

---Insert the active suggestion as one undo-friendly buffer edit.
---@return boolean accepted
function M.accept()
  if not is_valid(active) then
    M.clear()
    return false
  end

  local suggestion = active
  local lines = split_lines(suggestion.text)
  M.clear()

  local ok = pcall(
    vim.api.nvim_buf_set_text,
    suggestion.bufnr,
    suggestion.row - 1,
    suggestion.column,
    suggestion.row - 1,
    suggestion.column,
    lines
  )
  if not ok then
    return false
  end

  local end_row = suggestion.row + #lines - 1
  local end_column
  if #lines == 1 then
    end_column = suggestion.column + #lines[1]
  else
    end_column = #lines[#lines]
  end

  pcall(vim.api.nvim_win_set_cursor, suggestion.winid, { end_row, end_column })
  return true
end

---Expose the namespace for diagnostics and tests.
---@return integer
function M.namespace()
  return namespace
end

---Expose the dedicated highlight name for diagnostics and tests.
---@return string
function M.highlight_group()
  return highlight
end

return M
