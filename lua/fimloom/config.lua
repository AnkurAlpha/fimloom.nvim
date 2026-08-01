local providers = require("fimloom.providers")

local M = {}

local defaults = {
  enabled = true,
  provider = "ollama",
  completion = {
    mode = "fim",
    auto_trigger = true,
    debounce_ms = 180,
    trim_trailing_blank_lines = true,
    preserve_matching_prefix = true,
    context = {
      max_prefix_bytes = 12000,
      max_suffix_bytes = 4000,
      filetypes = {
        allow = {},
        deny = {},
      },
    },
    generation = {
      max_tokens = 128,
      temperature = 0.2,
    },
    preview = {
      max_bytes = 16 * 1024,
      max_lines = 100,
    },
  },
  ui = {
    suggestion = {
      fg = "#808080",
      ctermfg = 244,
      italic = false,
    },
    suggestion_hl = nil,
  },
  transport = {
    connect_timeout_ms = 1000,
    request_timeout_ms = 15000,
    max_response_bytes = 1024 * 1024,
  },
  server = {
    auto_start = false,
    auto_stop = true,
    startup_timeout_ms = 30000,
    startup_poll_interval_ms = 250,
  },
  log = {
    level = "warn",
    max_entries = 200,
    file = false,
    max_file_bytes = 512 * 1024,
    notify = true,
    notify_cooldown_ms = 5000,
  },
  keymaps = {
    accept = "<Tab>",
    dismiss = "<C-]>",
    manual = "<M-\\>",
  },
}

local function fail(path, message)
  error(string.format("fimloom.setup: %s %s", path, message), 3)
end

local function validate_boolean(path, value)
  if type(value) ~= "boolean" then
    fail(path, "must be a boolean")
  end
end

local function validate_table(path, value)
  if type(value) ~= "table" then
    fail(path, "must be a table")
  end
end

local function validate_integer(path, value, minimum, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 then
    fail(path, "must be an integer")
  end

  if value < minimum or value > maximum then
    fail(path, string.format("must be between %d and %d", minimum, maximum))
  end
end

local function validate_number(path, value, minimum, maximum)
  if type(value) ~= "number" or value ~= value then
    fail(path, "must be a finite number")
  end

  if value < minimum or value > maximum then
    fail(path, string.format("must be between %s and %s", minimum, maximum))
  end
end

local function validate_non_empty_string(path, value)
  if type(value) ~= "string" or value:match("^%s*$") then
    fail(path, "must be a non-empty string")
  end
end

local function normalize_endpoint(endpoint)
  validate_non_empty_string("endpoint", endpoint)

  local scheme, remainder = endpoint:match("^(https?)://(.+)$")
  if not scheme or not remainder or remainder:find("%s") then
    fail("endpoint", "must be an HTTP or HTTPS URL without whitespace")
  end

  if remainder:find("[?#]") then
    fail("endpoint", "must not contain a query string or fragment")
  end

  local authority = remainder:match("^([^/]+)") or ""
  if authority:find("@", 1, true) then
    fail("endpoint", "must not contain embedded user information")
  end

  return endpoint:gsub("/+$", "")
end

local function is_list(value)
  local checker = vim.islist or vim.tbl_islist
  return checker(value)
end

local function validate_command(command)
  if command == nil or type(command) == "function" then
    return
  end

  if type(command) ~= "table" or not is_list(command) or #command == 0 then
    fail("server.command", "must be a non-empty argument list, a function, or nil")
  end

  for index, argument in ipairs(command) do
    validate_non_empty_string(string.format("server.command[%d]", index), argument)
  end
end

local function validate_keymap(path, value)
  if value == false then
    return
  end

  validate_non_empty_string(path, value)
end

local function validate_string_list(path, value)
  if type(value) ~= "table" or not is_list(value) then
    fail(path, "must be a list of strings")
  end

  for index, item in ipairs(value) do
    validate_non_empty_string(string.format("%s[%d]", path, index), item)
  end
end

local function validate_log_file(value)
  if type(value) == "boolean" then
    return
  end

  validate_non_empty_string("log.file", value)
end

local function validate_ui(resolved)
  validate_table("ui", resolved.ui)
  validate_table("ui.suggestion", resolved.ui.suggestion)
  validate_non_empty_string("ui.suggestion.fg", resolved.ui.suggestion.fg)
  validate_integer("ui.suggestion.ctermfg", resolved.ui.suggestion.ctermfg, 0, 255)
  validate_boolean("ui.suggestion.italic", resolved.ui.suggestion.italic)

  if resolved.ui.suggestion_hl ~= nil then
    validate_non_empty_string("ui.suggestion_hl", resolved.ui.suggestion_hl)
  end
end

local function validate(resolved)
  validate_boolean("enabled", resolved.enabled)

  validate_non_empty_string("provider", resolved.provider)
  if not providers.get(resolved.provider) then
    fail("provider", string.format("has unknown provider %q", resolved.provider))
  end

  resolved.endpoint = normalize_endpoint(resolved.endpoint)

  if resolved.model ~= nil then
    validate_non_empty_string("model", resolved.model)
  end

  validate_table("completion", resolved.completion)
  if resolved.completion.mode ~= "fim" then
    fail("completion.mode", 'must be "fim" in the initial release')
  end

  validate_boolean("completion.auto_trigger", resolved.completion.auto_trigger)
  validate_integer("completion.debounce_ms", resolved.completion.debounce_ms, 0, 10000)
  validate_boolean(
    "completion.trim_trailing_blank_lines",
    resolved.completion.trim_trailing_blank_lines
  )
  validate_boolean(
    "completion.preserve_matching_prefix",
    resolved.completion.preserve_matching_prefix
  )
  validate_table("completion.context", resolved.completion.context)
  validate_integer(
    "completion.context.max_prefix_bytes",
    resolved.completion.context.max_prefix_bytes,
    0,
    1024 * 1024
  )
  validate_table("completion.generation", resolved.completion.generation)
  validate_integer(
    "completion.context.max_suffix_bytes",
    resolved.completion.context.max_suffix_bytes,
    0,
    1024 * 1024
  )
  validate_table("completion.context.filetypes", resolved.completion.context.filetypes)
  validate_string_list(
    "completion.context.filetypes.allow",
    resolved.completion.context.filetypes.allow
  )
  validate_string_list(
    "completion.context.filetypes.deny",
    resolved.completion.context.filetypes.deny
  )
  validate_integer(
    "completion.generation.max_tokens",
    resolved.completion.generation.max_tokens,
    1,
    4096
  )
  validate_number(
    "completion.generation.temperature",
    resolved.completion.generation.temperature,
    0,
    2
  )
  validate_table("completion.preview", resolved.completion.preview)
  validate_integer(
    "completion.preview.max_bytes",
    resolved.completion.preview.max_bytes,
    1,
    1024 * 1024
  )
  validate_integer("completion.preview.max_lines", resolved.completion.preview.max_lines, 1, 1000)

  validate_ui(resolved)

  validate_table("transport", resolved.transport)
  validate_integer("transport.connect_timeout_ms", resolved.transport.connect_timeout_ms, 1, 60000)
  validate_integer("transport.request_timeout_ms", resolved.transport.request_timeout_ms, 1, 600000)
  validate_integer(
    "transport.max_response_bytes",
    resolved.transport.max_response_bytes,
    1024,
    16 * 1024 * 1024
  )

  validate_table("server", resolved.server)
  validate_boolean("server.auto_start", resolved.server.auto_start)
  validate_boolean("server.auto_stop", resolved.server.auto_stop)
  validate_integer("server.startup_timeout_ms", resolved.server.startup_timeout_ms, 1, 600000)
  validate_integer(
    "server.startup_poll_interval_ms",
    resolved.server.startup_poll_interval_ms,
    10,
    10000
  )
  validate_command(resolved.server.command)
  if resolved.server.auto_start and resolved.server.command == nil then
    fail("server.command", "must be configured when server.auto_start is true")
  end

  validate_table("log", resolved.log)
  if
    not ({ off = true, error = true, warn = true, info = true, debug = true })[resolved.log.level]
  then
    fail("log.level", 'must be one of "off", "error", "warn", "info", or "debug"')
  end
  validate_integer("log.max_entries", resolved.log.max_entries, 1, 1000)
  validate_log_file(resolved.log.file)
  validate_integer("log.max_file_bytes", resolved.log.max_file_bytes, 1024, 16 * 1024 * 1024)
  validate_boolean("log.notify", resolved.log.notify)
  validate_integer("log.notify_cooldown_ms", resolved.log.notify_cooldown_ms, 0, 600000)

  validate_table("keymaps", resolved.keymaps)
  validate_keymap("keymaps.accept", resolved.keymaps.accept)
  validate_keymap("keymaps.dismiss", resolved.keymaps.dismiss)
  validate_keymap("keymaps.manual", resolved.keymaps.manual)
end

---Return a defensive copy of the default configuration.
---@return table
function M.defaults()
  return vim.deepcopy(defaults)
end

---Resolve and validate user options.
---@param options? table
---@return table
function M.resolve(options)
  options = options or {}

  if type(options) ~= "table" then
    error("fimloom.setup: expected a table or nil", 2)
  end

  local resolved = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.deepcopy(options))
  local provider = providers.get(resolved.provider)

  if resolved.endpoint == nil and provider then
    resolved.endpoint = provider.default_endpoint
  end

  validate(resolved)

  return resolved
end

return M
