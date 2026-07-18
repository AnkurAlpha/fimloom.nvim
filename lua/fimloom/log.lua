local uv = vim.uv or vim.loop

local M = {}

local levels = {
  debug = 1,
  info = 2,
  warn = 3,
  error = 4,
  off = 5,
}

local notify_levels = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

local sensitive_keys = {
  body = true,
  completion = true,
  context = true,
  input_prefix = true,
  input_suffix = true,
  prefix = true,
  prompt = true,
  request_body = true,
  response = true,
  source = true,
  suffix = true,
  text = true,
}

local function join_path(left, right)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(left, right)
  end
  return left:gsub("/+$", "") .. "/" .. right
end

local default_dependencies = {
  notify = vim.notify,
  now_ms = function()
    return uv.hrtime() / 1000000
  end,
  stdpath = function(kind)
    return vim.fn.stdpath(kind)
  end,
  expand = function(path)
    return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  end,
  mkdir = function(path)
    return vim.fn.mkdir(path, "p")
  end,
  file_size = function(path)
    return vim.fn.getfsize(path)
  end,
  write_lines = function(path, lines, append)
    return vim.fn.writefile(lines, path, append and "a" or "")
  end,
  timestamp = function()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
  end,
}

local dependencies = default_dependencies
local runtime_config
local entries = {}
local notification_times = {}
local file_path
local last_file_error

local function truncate(value, maximum)
  if #value <= maximum then
    return value
  end
  return value:sub(1, maximum - 3) .. "..."
end

local function sanitize(value, key, depth)
  if type(key) == "string" and sensitive_keys[key:lower()] then
    return "<redacted>"
  end

  local value_type = type(value)
  if value_type == "string" then
    return truncate(value, 1024)
  end
  if value_type == "number" or value_type == "boolean" or value == nil then
    return value
  end
  if value_type ~= "table" then
    return string.format("<%s>", value_type)
  end
  if depth >= 4 then
    return "<max-depth>"
  end

  local result = {}
  local count = 0
  for child_key, child_value in pairs(value) do
    count = count + 1
    if count > 32 then
      result["<truncated>"] = true
      break
    end
    result[child_key] = sanitize(child_value, child_key, depth + 1)
  end
  return result
end

local function logging_enabled(level)
  return runtime_config
    and runtime_config.level ~= "off"
    and levels[level] >= levels[runtime_config.level]
end

local function resolve_file_path(file)
  if file == false then
    return nil
  end

  local path = file
  if file == true then
    local ok, base = pcall(dependencies.stdpath, "log")
    if not ok then
      ok, base = pcall(dependencies.stdpath, "state")
    end
    if not ok then
      return nil, string.format("could not resolve Neovim's log directory: %s", base)
    end
    path = join_path(base, "fimloom.log")
  end

  local ok, expanded = pcall(dependencies.expand, path)
  if not ok then
    return nil, string.format("could not resolve log.file: %s", expanded)
  end
  return expanded
end

local function encoded_entry(entry)
  local ok, encoded = pcall(vim.json.encode, entry)
  if not ok then
    return nil, tostring(encoded)
  end
  return encoded
end

local function bounded_file_lines()
  local selected = {}
  local size = 0

  for index = #entries, 1, -1 do
    local line = encoded_entry(entries[index])
    if line then
      if #line + 1 > runtime_config.max_file_bytes then
        line = assert(encoded_entry({
          timestamp = entries[index].timestamp,
          level = entries[index].level,
          event = entries[index].event,
          fields = { truncated = true },
        }))
      end

      if size + #line + 1 > runtime_config.max_file_bytes then
        break
      end
      table.insert(selected, 1, line)
      size = size + #line + 1
    end
  end

  return selected
end

local function persist(entry)
  if not file_path then
    return
  end

  local line, encode_error = encoded_entry(entry)
  if not line then
    last_file_error = string.format("could not encode diagnostic entry: %s", encode_error)
    return
  end

  local size_ok, current_size = pcall(dependencies.file_size, file_path)
  current_size = size_ok and math.max(current_size, 0) or 0
  local append = current_size + #line + 1 <= runtime_config.max_file_bytes
  local lines = append and { line } or bounded_file_lines()
  local ok, result = pcall(dependencies.write_lines, file_path, lines, append)
  if not ok or (type(result) == "number" and result ~= 0) then
    last_file_error = string.format("could not write diagnostics: %s", tostring(result))
  else
    last_file_error = nil
  end
end

---Configure bounded diagnostics.
---@param config table Resolved FIMLoom configuration or its log section.
---@param injected? table Internal dependency overrides used by tests.
function M.setup(config, injected)
  if type(config) ~= "table" then
    error("fimloom.log.setup: expected a resolved configuration table", 2)
  end

  dependencies = vim.tbl_extend("force", {}, default_dependencies, injected or {})
  runtime_config = vim.deepcopy(config.log or config)
  entries = {}
  notification_times = {}
  last_file_error = nil
  file_path, last_file_error = resolve_file_path(runtime_config.file)

  if file_path then
    local parent = vim.fn.fnamemodify(file_path, ":h")
    local ok, result = pcall(dependencies.mkdir, parent)
    if not ok or (type(result) == "number" and result == 0 and vim.fn.isdirectory(parent) ~= 1) then
      last_file_error = string.format("could not create log directory: %s", tostring(result))
      file_path = nil
    end
  end
end

---Record a privacy-filtered diagnostic event.
---@param level string
---@param event string
---@param fields? table
---@return boolean recorded
function M.write(level, event, fields)
  if not levels[level] then
    error("fimloom.log.write: unknown log level", 2)
  end
  if type(event) ~= "string" or event:match("^%s*$") then
    error("fimloom.log.write: event must be a non-empty string", 2)
  end
  if fields ~= nil and type(fields) ~= "table" then
    error("fimloom.log.write: fields must be a table or nil", 2)
  end
  if not logging_enabled(level) then
    return false
  end

  local entry = {
    timestamp = dependencies.timestamp(),
    level = level,
    event = event,
    fields = sanitize(fields or {}, nil, 0),
  }
  entries[#entries + 1] = entry
  while #entries > runtime_config.max_entries do
    table.remove(entries, 1)
  end
  persist(entry)
  return true
end

---Show a diagnostic notification with per-key cooldown.
---@param key string
---@param message string
---@param level? string
---@param options? table
---@return boolean displayed
function M.notify(key, message, level, options)
  if type(key) ~= "string" or key:match("^%s*$") then
    error("fimloom.log.notify: key must be a non-empty string", 2)
  end
  if type(message) ~= "string" or message:match("^%s*$") then
    error("fimloom.log.notify: message must be a non-empty string", 2)
  end

  level = level or "warn"
  options = options or {}
  M.write(level, options.event or "notification", {
    key = key,
    message = message,
  })

  local force = options.force == true
  if not force and (not runtime_config or not runtime_config.notify) then
    return false
  end

  local now = dependencies.now_ms()
  local previous = notification_times[key]
  local cooldown = runtime_config and runtime_config.notify_cooldown_ms or 0
  if not force and previous and now - previous < cooldown then
    return false
  end
  notification_times[key] = now

  pcall(dependencies.notify, truncate(message, 1024), notify_levels[level] or vim.log.levels.INFO, {
    title = "FIMLoom",
  })
  return true
end

---Return defensive copies of retained in-memory entries.
---@return table[]
function M.entries()
  return vim.deepcopy(entries)
end

---Return serializable diagnostic metadata.
---@return table
function M.status()
  return {
    configured = runtime_config ~= nil,
    level = runtime_config and runtime_config.level or "off",
    entry_count = #entries,
    file = file_path,
    file_error = last_file_error,
  }
end

---Reset diagnostics. Intended for internal cleanup and tests.
function M.shutdown()
  runtime_config = nil
  dependencies = default_dependencies
  entries = {}
  notification_times = {}
  file_path = nil
  last_file_error = nil
end

return M
