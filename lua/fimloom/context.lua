local M = {}

local LINE_CHUNK_SIZE = 128

local function is_continuation_byte(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

local function take_head_utf8(value, limit)
  if limit <= 0 then
    return ""
  end

  if #value <= limit then
    return value
  end

  local finish = limit
  if is_continuation_byte(value:byte(finish + 1)) then
    while finish > 0 and is_continuation_byte(value:byte(finish)) do
      finish = finish - 1
    end
    finish = finish - 1
  end

  return finish > 0 and value:sub(1, finish) or ""
end

local function take_tail_utf8(value, limit)
  if limit <= 0 then
    return ""
  end

  if #value <= limit then
    return value
  end

  local start = #value - limit + 1
  while start <= #value and is_continuation_byte(value:byte(start)) do
    start = start + 1
  end

  return value:sub(start)
end

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end

  return false
end

local function filetype_allowed(filetype, context_config)
  local filetypes = context_config.filetypes or {}
  local allow = filetypes.allow or {}
  local deny = filetypes.deny or {}

  if #allow > 0 and not contains(allow, filetype) then
    return false
  end

  return not contains(deny, filetype)
end

local function suitability(bufnr, context_config)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false, "buffer is not loaded"
  end

  if not vim.bo[bufnr].modifiable then
    return false, "buffer is not modifiable"
  end

  if vim.bo[bufnr].readonly then
    return false, "buffer is readonly"
  end

  if vim.bo[bufnr].binary then
    return false, "binary buffers are not supported"
  end

  if vim.bo[bufnr].buftype ~= "" then
    return false, string.format("buffer type %q is not supported", vim.bo[bufnr].buftype)
  end

  if not filetype_allowed(vim.bo[bufnr].filetype, context_config) then
    return false, string.format("filetype %q is not enabled", vim.bo[bufnr].filetype)
  end

  return true
end

local function collect_prefix(bufnr, row, column, current_line, limit)
  local current = current_line:sub(1, column)
  local bounded = take_tail_utf8(current, limit)
  if #bounded < #current or #bounded >= limit then
    return bounded
  end

  local preceding = {}
  local remaining = limit - #bounded
  local line_index = row - 2

  while line_index >= 0 and remaining > 0 do
    local chunk_start = math.max(0, line_index - LINE_CHUNK_SIZE + 1)
    local lines = vim.api.nvim_buf_get_lines(bufnr, chunk_start, line_index + 1, false)

    for index = #lines, 1, -1 do
      local fragment = lines[index] .. "\n"
      local piece = take_tail_utf8(fragment, remaining)
      preceding[#preceding + 1] = piece
      remaining = remaining - #piece

      if #piece < #fragment or remaining == 0 then
        line_index = -1
        break
      end
    end

    if line_index >= 0 then
      line_index = chunk_start - 1
    end
  end

  local parts = {}
  for index = #preceding, 1, -1 do
    parts[#parts + 1] = preceding[index]
  end
  parts[#parts + 1] = bounded
  return table.concat(parts)
end

local function collect_suffix(bufnr, row, column, current_line, line_count, limit)
  local current = current_line:sub(column + 1)
  local bounded = take_head_utf8(current, limit)
  if #bounded < #current or #bounded >= limit then
    return bounded
  end

  local parts = { bounded }
  local remaining = limit - #bounded
  local line_index = row

  while line_index < line_count and remaining > 0 do
    local chunk_end = math.min(line_count, line_index + LINE_CHUNK_SIZE)
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_index, chunk_end, false)

    for _, line in ipairs(lines) do
      local fragment = "\n" .. line
      local piece = take_head_utf8(fragment, remaining)
      parts[#parts + 1] = piece
      remaining = remaining - #piece

      if #piece < #fragment or remaining == 0 then
        line_index = line_count
        break
      end
    end

    if line_index < line_count then
      line_index = chunk_end
    end
  end

  return table.concat(parts)
end

---Capture bounded fill-in-the-middle context at a window cursor.
---@param config table
---@param bufnr? integer
---@param winid? integer
---@return table? context
---@return string? reason
function M.capture(config, bufnr, winid)
  if type(config) ~= "table" or type(config.completion) ~= "table" then
    error("fimloom.context.capture: expected a resolved configuration table", 2)
  end

  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return nil, "window is not valid"
  end

  bufnr = bufnr or vim.api.nvim_win_get_buf(winid)
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil, "window does not display the requested buffer"
  end

  local context_config = config.completion.context
  local suitable, reason = suitability(bufnr, context_config)
  if not suitable then
    return nil, reason
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row = cursor[1]
  local current_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local column = math.min(cursor[2], #current_line)
  local name = vim.api.nvim_buf_get_name(bufnr)

  if name ~= "" then
    name = vim.fn.fnamemodify(name, ":p")
  end

  return {
    bufnr = bufnr,
    winid = winid,
    filename = name,
    filetype = vim.bo[bufnr].filetype,
    row = row,
    column = column,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    prefix = collect_prefix(bufnr, row, column, current_line, context_config.max_prefix_bytes),
    suffix = collect_suffix(
      bufnr,
      row,
      column,
      current_line,
      vim.api.nvim_buf_line_count(bufnr),
      context_config.max_suffix_bytes
    ),
    indentation = current_line:match("^%s*") or "",
  }
end

---Return whether a captured anchor still matches live editor state.
---@param context table
---@return boolean
function M.is_current(context)
  if type(context) ~= "table" then
    return false
  end

  if
    not vim.api.nvim_buf_is_valid(context.bufnr) or not vim.api.nvim_buf_is_loaded(context.bufnr)
  then
    return false
  end

  if not vim.api.nvim_win_is_valid(context.winid) then
    return false
  end

  if vim.api.nvim_win_get_buf(context.winid) ~= context.bufnr then
    return false
  end

  if vim.api.nvim_buf_get_changedtick(context.bufnr) ~= context.changedtick then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(context.winid)
  return cursor[1] == context.row and cursor[2] == context.column
end

return M
