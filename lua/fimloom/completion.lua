local context_module = require("fimloom.context")
local log = require("fimloom.log")
local providers_module = require("fimloom.providers")
local render_module = require("fimloom.render")
local state = require("fimloom.state")

local M = {}

local default_dependencies = {
  context = context_module,
  providers = providers_module,
  render = render_module,
}
local dependencies = default_dependencies
local runtime_config
local debounce_timer
local active_request
local augroup
local mappings = {}

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

local function stop_timer()
  if not debounce_timer then
    return false
  end

  local timer = debounce_timer
  debounce_timer = nil
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  return true
end

local function cancel_request()
  if not active_request then
    return false
  end

  local request = active_request
  active_request = nil
  if request.handle and type(request.handle.cancel) == "function" then
    pcall(request.handle.cancel, request.handle)
  end
  return true
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

---Normalize and validate provider completion text.
---@param text string
---@param suffix string
---@param limits? table
---@return string?
function M.sanitize(text, suffix, limits)
  if type(text) ~= "string" then
    return nil
  end

  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = strip_code_fence(text)
  text = remove_suffix_overlap(text, suffix or "")
  limits = limits or {
    max_bytes = 16 * 1024,
    max_lines = 100,
  }
  text = limit_lines(text, limits.max_lines)
  text = take_head_utf8(text, limits.max_bytes)

  if not text:find("%S") then
    return nil
  end

  if suffix and suffix:sub(1, #text) == text then
    return nil
  end

  return text
end

local function finish_request(request_id, captured, response)
  if not active_request or active_request.id ~= request_id then
    return
  end

  local manual = active_request.manual
  active_request = nil
  if not state.is_enabled() then
    dependencies.render.clear()
    return
  end

  if not response or not response.ok then
    local kind = response and response.error and response.error.kind or "unknown"
    local message = response and response.error and response.error.message
      or "completion request failed"
    log.notify(
      "completion:" .. kind,
      string.format("FIMLoom completion failed: %s", tostring(message)),
      "warn",
      { force = manual }
    )
    dependencies.render.clear()
    return
  end

  if not dependencies.context.is_current(captured) then
    return
  end

  local text = M.sanitize(response.text, captured.suffix, runtime_config.completion.preview)
  if not text then
    return
  end

  dependencies.render.show(captured, text)
end

local function request_completion(manual)
  if not runtime_config or not state.is_enabled() then
    return false, "FIMLoom is not enabled"
  end

  if not manual and vim.fn.pumvisible() == 1 then
    return false, "completion popup is visible"
  end

  stop_timer()
  cancel_request()
  dependencies.render.clear()

  local captured, capture_error = dependencies.context.capture(runtime_config)
  if not captured then
    return false, capture_error
  end

  local request_id = state.next_request_id()
  local record = {
    id = request_id,
    context = captured,
    handle = nil,
    manual = manual == true,
  }
  active_request = record

  local ok, handle_or_error = pcall(
    dependencies.providers.complete,
    captured,
    runtime_config,
    function(response)
      vim.schedule(function()
        finish_request(request_id, captured, response)
      end)
    end
  )

  if not ok then
    if active_request == record then
      active_request = nil
    end
    log.notify(
      "completion:start",
      string.format("FIMLoom could not start a completion request: %s", tostring(handle_or_error)),
      "warn",
      { force = manual == true }
    )
    return false, tostring(handle_or_error)
  end

  record.handle = handle_or_error
  return true
end

local function schedule_completion()
  stop_timer()

  local delay = runtime_config.completion.debounce_ms
  if delay == 0 then
    return request_completion()
  end

  local timer
  timer = vim.defer_fn(function()
    if debounce_timer ~= timer then
      return
    end

    debounce_timer = nil
    request_completion(false)
  end, delay)
  debounce_timer = timer
  return true
end

local function passthrough(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, false, true)
end

local function mapping_is_available(lhs)
  local existing = vim.fn.maparg(lhs, "i", false, true)
  return type(existing) ~= "table" or vim.tbl_isempty(existing)
end

local function add_mapping(lhs, callback, options, force)
  if lhs == false then
    return
  end

  if not force and not mapping_is_available(lhs) then
    return
  end

  vim.keymap.set("i", lhs, callback, options)
  mappings[#mappings + 1] = {
    lhs = lhs,
    desc = options.desc,
  }
end

local function register_mappings(config)
  local accept = config.keymaps.accept
  add_mapping(accept, function()
    if dependencies.render.has_suggestion() then
      -- Expression mappings run under textlock. Schedule acceptance so the
      -- buffer edit happens after Neovim finishes evaluating this keypress.
      vim.schedule(M.accept)
      return ""
    end
    return passthrough(accept)
  end, {
    desc = "FIMLoom: accept inline suggestion",
    expr = true,
    nowait = true,
    silent = true,
  }, true)

  local dismiss = config.keymaps.dismiss
  add_mapping(dismiss, function()
    if M.dismiss() then
      return ""
    end
    return passthrough(dismiss)
  end, {
    desc = "FIMLoom: dismiss inline suggestion",
    expr = true,
    silent = true,
  })

  add_mapping(config.keymaps.manual, function()
    M.trigger({ manual = true })
  end, {
    desc = "FIMLoom: request inline suggestion",
    silent = true,
  })
end

local function remove_mappings()
  for _, mapping in ipairs(mappings) do
    local current = vim.fn.maparg(mapping.lhs, "i", false, true)
    if type(current) == "table" and current.desc == mapping.desc then
      pcall(vim.keymap.del, "i", mapping.lhs)
    end
  end
  mappings = {}
end

---Handle an insert-mode text change. Exposed for deterministic tests.
function M._on_text_changed()
  if not runtime_config or not state.is_enabled() then
    return false
  end

  cancel_request()
  dependencies.render.clear()

  if not runtime_config.completion.auto_trigger or vim.fn.pumvisible() == 1 then
    stop_timer()
    return false
  end

  return schedule_completion()
end

---Handle insert-mode cursor movement without starting work.
function M._on_cursor_moved()
  if dependencies.render.has_suggestion() and not dependencies.render.is_current() then
    dependencies.render.clear()
  end

  if active_request and not dependencies.context.is_current(active_request.context) then
    cancel_request()
  end
end

local function register_autocmds()
  augroup = vim.api.nvim_create_augroup("FIMLoomCompletion", { clear = true })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      M._on_text_changed()
    end,
    desc = "Schedule a FIMLoom inline completion",
  })

  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    callback = function()
      M._on_cursor_moved()
    end,
    desc = "Invalidate stale FIMLoom inline work",
  })

  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufWipeout" }, {
    group = augroup,
    callback = function()
      M.dismiss()
    end,
    desc = "Clear FIMLoom inline work",
  })
end

---Initialize the completion runtime.
---@param config table
---@param injected? table Internal dependency overrides used by tests.
function M.setup(config, injected)
  if type(config) ~= "table" then
    error("fimloom.completion.setup: expected a resolved configuration table", 2)
  end

  M.shutdown()
  dependencies = {
    context = (injected and injected.context) or context_module,
    providers = (injected and injected.providers) or providers_module,
    render = (injected and injected.render) or render_module,
  }
  runtime_config = vim.deepcopy(config)
  dependencies.render.setup()
  register_autocmds()
  register_mappings(runtime_config)
end

---Request a completion immediately.
---@param options? table
---@return boolean started
---@return string? reason
function M.trigger(options)
  options = options or {}
  if type(options) ~= "table" then
    error("fimloom.completion.trigger: expected a table or nil", 2)
  end

  return request_completion(options.manual == true)
end

---Accept the active suggestion.
---@return boolean accepted
function M.accept()
  stop_timer()
  cancel_request()
  return dependencies.render.accept()
end

---Dismiss timers, requests, and the active suggestion.
---@return boolean dismissed
function M.dismiss()
  local dismissed = stop_timer()
  dismissed = cancel_request() or dismissed
  dismissed = dependencies.render.clear() or dismissed
  return dismissed
end

---Tear down completion hooks and pending work. Safe to call repeatedly.
function M.shutdown()
  M.dismiss()
  remove_mappings()

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end

  runtime_config = nil
  dependencies = default_dependencies
end

---Return serializable completion runtime metadata.
---@return table
function M.status()
  local suggestion = dependencies.render.get()
  return {
    configured = runtime_config ~= nil,
    debounce_pending = debounce_timer ~= nil,
    active_request_id = active_request and active_request.id or nil,
    suggestion = suggestion and {
      bufnr = suggestion.bufnr,
      row = suggestion.row,
      column = suggestion.column,
      bytes = #suggestion.text,
    } or nil,
  }
end

return M
