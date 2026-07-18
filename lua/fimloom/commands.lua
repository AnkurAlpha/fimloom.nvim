local log_module = require("fimloom.log")

local M = {}

local subcommands = {
  "accept",
  "complete",
  "disable",
  "dismiss",
  "enable",
  "start",
  "status",
  "stop",
  "toggle",
}

local default_dependencies = {
  api = function()
    return require("fimloom")
  end,
  log = log_module,
}

local dependencies = default_dependencies
local registered = false

local function api()
  if type(dependencies.api) == "function" then
    return dependencies.api()
  end
  return dependencies.api
end

local function require_setup(fimloom)
  if not fimloom.is_configured() then
    return false, "FIMLoom is not configured; call require('fimloom').setup() first", "error"
  end
  return true
end

local function format_status(status)
  if not status.configured then
    return "FIMLoom is not configured"
  end

  local ownership = status.server.owned and "owned" or "external/unowned"
  local parts = {
    status.enabled and "enabled" or "disabled",
    "provider=" .. status.provider,
    "endpoint=" .. status.endpoint,
    string.format("server=%s (%s)", status.server.status, ownership),
  }
  if status.model then
    parts[#parts + 1] = "model=" .. status.model
  end
  if status.server.error_kind then
    parts[#parts + 1] = "error=" .. status.server.error_kind
  end
  return "FIMLoom: " .. table.concat(parts, " | ")
end

local handlers = {
  enable = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    if fimloom.is_enabled() then
      return true, "FIMLoom is already enabled", "info"
    end
    fimloom.enable()
    return true, "FIMLoom enabled", "info"
  end,
  disable = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    if not fimloom.is_enabled() then
      return true, "FIMLoom is already disabled", "info"
    end
    fimloom.disable()
    return true, "FIMLoom disabled", "info"
  end,
  toggle = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    local enabled = fimloom.toggle()
    return true, enabled and "FIMLoom enabled" or "FIMLoom disabled", "info"
  end,
  complete = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    local started, reason = fimloom.complete()
    if not started then
      return false, reason or "FIMLoom could not request a completion", "warn"
    end
    return true, "FIMLoom completion requested", "info"
  end,
  accept = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    if not fimloom.accept() then
      return false, "FIMLoom has no inline suggestion to accept", "info"
    end
    return true, "FIMLoom suggestion accepted", "info"
  end,
  dismiss = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    if not fimloom.dismiss() then
      return false, "FIMLoom has no pending work or suggestion to dismiss", "info"
    end
    return true, "FIMLoom suggestion dismissed", "info"
  end,
  start = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    local started, reason = fimloom.start()
    if not started then
      return false, reason or "FIMLoom could not start the configured server", "info"
    end
    return true, "FIMLoom server readiness probe started", "info"
  end,
  stop = function(fimloom)
    local ok, message, level = require_setup(fimloom)
    if not ok then
      return ok, message, level
    end
    if not fimloom.stop() then
      return false, "FIMLoom has no owned server work to stop", "info"
    end
    return true, "FIMLoom stopped its owned server work", "info"
  end,
  status = function(fimloom)
    return true, format_status(fimloom.status()), "info"
  end,
}

---Execute one FIMLoom subcommand.
---@param name string
---@return boolean ok
---@return string message
function M.execute(name)
  name = type(name) == "string" and name:lower() or ""
  local handler = handlers[name]
  if not handler then
    local message = string.format("Unknown FIMLoom subcommand %q", name)
    dependencies.log.notify("command:unknown", message, "error", {
      force = true,
      event = "command",
    })
    return false, message
  end

  local called, ok, message, level = pcall(function()
    return handler(api())
  end)
  if not called then
    local failure = ok
    ok = false
    message = string.format("FIMLoom %s failed: %s", name, tostring(failure))
    level = "error"
  end

  dependencies.log.notify("command:" .. name, message, level, {
    force = true,
    event = "command",
  })
  return ok, message
end

---Return matching subcommands for command-line completion.
---@param prefix? string
---@return string[]
function M.complete(prefix)
  prefix = (prefix or ""):lower()
  local matches = {}
  for _, name in ipairs(subcommands) do
    if name:sub(1, #prefix) == prefix then
      matches[#matches + 1] = name
    end
  end
  return matches
end

---Register the :FIMLoom command once.
---@param injected? table Internal dependency overrides used by tests.
---@return boolean registered_now
---@return string? reason
function M.setup(injected)
  dependencies = vim.tbl_extend("force", {}, default_dependencies, injected or {})
  if registered then
    return false, "already registered"
  end
  if vim.fn.exists(":FIMLoom") == 2 then
    return false, ":FIMLoom already exists"
  end

  vim.api.nvim_create_user_command("FIMLoom", function(options)
    M.execute(options.args)
  end, {
    nargs = 1,
    complete = function(argument_lead)
      return M.complete(argument_lead)
    end,
    desc = "Control FIMLoom local inline completion",
  })
  registered = true
  return true
end

---Remove the command created by this module. Intended for tests.
function M.shutdown()
  if registered then
    pcall(vim.api.nvim_del_user_command, "FIMLoom")
    registered = false
  end
  dependencies = default_dependencies
end

return M
