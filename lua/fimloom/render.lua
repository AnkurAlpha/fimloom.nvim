local M = {}

local namespace = vim.api.nvim_create_namespace("fimloom")
local highlight = "FIMLoomSuggestion"
local active

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

---Define the default suggestion highlight without overriding user colors.
function M.setup()
  vim.api.nvim_set_hl(0, highlight, {
    default = true,
    link = "Comment",
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

  local mark_id =
    vim.api.nvim_buf_set_extmark(context.bufnr, namespace, context.row - 1, context.column, options)

  active = {
    bufnr = context.bufnr,
    winid = context.winid,
    row = context.row,
    column = context.column,
    changedtick = context.changedtick,
    text = text,
    mark_id = mark_id,
  }
  return true
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

return M
