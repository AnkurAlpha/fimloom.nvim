local M = {}

local function is_continuation_byte(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

local function take_head_utf8(value, limit)
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

local function limit_lines(text, maximum)
  local search_from = 1
  for line = 1, maximum do
    local newline = text:find("\n", search_from, true)
    if not newline then
      return text
    end

    if line == maximum then
      return text:sub(1, newline - 1)
    end

    search_from = newline + 1
  end

  return text
end

local function remove_suffix_overlap(text, suffix)
  local maximum = math.min(#text, #suffix)
  for length = maximum, 1, -1 do
    if text:sub(#text - length + 1) == suffix:sub(1, length) then
      return text:sub(1, #text - length)
    end
  end

  local compact_text = text:gsub("%s", "")
  local compact_suffix = suffix:gsub("%s", "")
  maximum = math.min(#compact_text, #compact_suffix)
  for length = maximum, 1, -1 do
    local overlap = compact_suffix:sub(1, length)
    local safe_fuzzy_overlap = length >= 3 or overlap:match("^%p+$") ~= nil
    if safe_fuzzy_overlap and compact_text:sub(#compact_text - length + 1) == overlap then
      local seen = 0
      local start = #text + 1

      for index = #text, 1, -1 do
        if not text:sub(index, index):match("%s") then
          seen = seen + 1
        end

        if seen == length then
          start = index
          break
        end
      end

      local first = text:sub(start, start)
      local preceding = start > 1 and text:sub(start - 1, start - 1) or ""
      local inside_identifier = first:match("[%w_]") and preceding:match("[%w_]")
      if not inside_identifier then
        return text:sub(1, start - 1):gsub("[ \t]+$", "")
      end
    end
  end

  return text
end

local function strip_code_fence(text)
  local _, opening_end = text:find("^[ \t]*```[^\n]*\n")
  if not opening_end then
    return text
  end

  return text:sub(opening_end + 1):gsub("\n[ \t]*```[ \t]*$", "")
end

local function trim_trailing_blank_lines(text)
  while true do
    local trimmed, count = text:gsub("\n[ \t]*$", "")
    text = trimmed
    if count == 0 then
      return text
    end
  end
end

---Normalize and validate provider completion text.
---@param text string
---@param suffix string
---@param options? table
---@return string?
function M.sanitize(text, suffix, options)
  if type(text) ~= "string" then
    return nil
  end

  options = options or {}
  local max_bytes = options.max_bytes or 16 * 1024
  local max_lines = options.max_lines or 100
  local should_trim = options.trim_trailing_blank_lines ~= false

  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = strip_code_fence(text)
  text = remove_suffix_overlap(text, suffix or "")
  text = limit_lines(text, max_lines)
  text = take_head_utf8(text, max_bytes)
  if should_trim then
    text = trim_trailing_blank_lines(text)
  end

  if not text:find("%S") then
    return nil
  end

  if suffix and suffix:sub(1, #text) == text then
    return nil
  end

  return text
end

return M
