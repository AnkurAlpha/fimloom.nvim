local log_module = require("fimloom.log")
local providers_module = require("fimloom.providers")
local state_module = require("fimloom.state")

local M = {}

local default_dependencies = {
  state = state_module,
  providers = providers_module,
  log = log_module,
  has = function(feature)
    return vim.fn.has(feature)
  end,
  executable = function(command)
    return vim.fn.executable(command)
  end,
  version = vim.version,
  wait = vim.wait,
}

local function item(level, message, advice)
  return {
    level = level,
    message = message,
    advice = advice,
  }
end

local function is_loopback(endpoint)
  local authority = endpoint:match("^https?://([^/]+)") or ""
  local host = authority:gsub(":%d+$", ""):lower()
  return host == "127.0.0.1" or host == "localhost" or host == "[::1]"
end

local function configured_checks(report, dependencies, config)
  report[#report + 1] = item("ok", "FIMLoom setup has completed")
  report[#report + 1] = item("info", "Provider: " .. config.provider)
  report[#report + 1] = item("info", "Endpoint: " .. config.endpoint)

  if is_loopback(config.endpoint) then
    report[#report + 1] = item("ok", "The configured endpoint is loopback-local")
  else
    report[#report + 1] = item(
      "warn",
      "The configured endpoint is not loopback-local; buffer context will leave this machine",
      "Use 127.0.0.1, localhost, or [::1] for a local-only endpoint"
    )
  end

  if config.model then
    report[#report + 1] = item("info", "Model: " .. config.model)
  elseif config.provider == "ollama" then
    report[#report + 1] = item(
      "error",
      "No Ollama model is configured",
      "Set opts.model to an installed Ollama model name"
    )
  else
    report[#report + 1] = item(
      "warn",
      "No model path is recorded in FIMLoom configuration",
      "Set opts.model so diagnostics describe the llama.cpp model selected by the startup command"
    )
  end

  local command = config.server.command
  if type(command) == "table" then
    if dependencies.executable(command[1]) == 1 then
      report[#report + 1] = item("ok", "Startup executable is available: " .. command[1])
    else
      report[#report + 1] = item(
        "error",
        "Startup executable is not available: " .. command[1],
        "Install it or correct opts.server.command"
      )
    end
  elseif type(command) == "function" then
    report[#report + 1] = item(
      "info",
      "The startup command is dynamic; its returned executable is validated when starting"
    )
  else
    report[#report + 1] =
      item("info", "Automatic server startup is disabled and no startup command is configured")
  end

  local server = dependencies.state.get_server()
  local ownership = server.owned and "owned by this Neovim instance" or "external or unowned"
  local server_level = server.status == "ready" and "ok" or "info"
  if server.status == "starting" or server.status == "failed" then
    server_level = "warn"
  end
  report[#report + 1] =
    item(server_level, string.format("Server state: %s (%s)", server.status, ownership))
  if server.error then
    report[#report + 1] = item("warn", "Last server error category: " .. server.error.kind)
  end
end

local function provider_check(report, dependencies, config)
  local probe_config = vim.deepcopy(config)
  probe_config.transport.connect_timeout_ms =
    math.min(probe_config.transport.connect_timeout_ms, 1000)
  probe_config.transport.request_timeout_ms =
    math.min(probe_config.transport.request_timeout_ms, 5000)
  local result
  local ok, request_or_error = pcall(dependencies.providers.health, probe_config, function(response)
    result = response
  end)
  if not ok then
    report[#report + 1] =
      item("error", "Provider health probe could not start: " .. tostring(request_or_error))
    return
  end

  local completed = dependencies.wait(probe_config.transport.request_timeout_ms + 500, function()
    return result ~= nil
  end, 10)
  if not completed then
    if request_or_error and type(request_or_error.cancel) == "function" then
      pcall(request_or_error.cancel, request_or_error)
    end
    report[#report + 1] = item(
      "error",
      "Provider health probe timed out",
      "Check the endpoint, server logs, and transport.request_timeout_ms"
    )
    return
  end

  if not result or not result.ok or not result.ready then
    local kind = result and result.error and result.error.kind or "not_ready"
    local message = result and result.error and result.error.message
      or "provider did not report readiness"
    report[#report + 1] = item(
      "error",
      string.format("Provider health failed (%s): %s", tostring(kind), tostring(message)),
      "Start the configured local server or review :FIMLoom status"
    )
    return
  end

  report[#report + 1] = item("ok", "Provider endpoint is reachable and ready")
  if result.model_available == false then
    report[#report + 1] = item(
      "error",
      "The configured Ollama model is not installed",
      "Install the configured model explicitly with Ollama before requesting completions"
    )
  elseif result.model_available == true then
    report[#report + 1] = item("ok", "The configured Ollama model is installed")
  end
end

---Collect privacy-safe health results.
---@param injected? table Internal dependency overrides used by tests.
---@return table[] report
function M.collect(injected)
  local dependencies = vim.tbl_extend("force", {}, default_dependencies, injected or {})
  local report = {}
  local version = dependencies.version()

  if dependencies.has("nvim-0.10") == 1 then
    report[#report + 1] = item(
      "ok",
      string.format("Neovim %d.%d.%d is supported", version.major, version.minor, version.patch)
    )
  else
    report[#report + 1] = item(
      "error",
      string.format("Neovim %d.%d.%d is unsupported", version.major, version.minor, version.patch),
      "Upgrade to Neovim 0.10 or newer"
    )
  end

  local curl_available = dependencies.executable("curl") == 1
  report[#report + 1] = curl_available and item("ok", "curl is executable")
    or item("error", "curl is not executable", "Install curl and ensure it is on $PATH")

  if not dependencies.state.is_configured() then
    report[#report + 1] = item(
      "error",
      "FIMLoom setup has not run",
      "Call require('fimloom').setup({...}) from your Neovim configuration"
    )
  else
    local config = dependencies.state.get_config()
    configured_checks(report, dependencies, config)
    if curl_available then
      provider_check(report, dependencies, config)
    end
  end

  local diagnostics = dependencies.log.status()
  if diagnostics.file then
    report[#report + 1] = item("info", "Diagnostic log: " .. diagnostics.file)
  else
    report[#report + 1] = item("info", "Persistent diagnostic logging is disabled")
  end
  if diagnostics.file_error then
    report[#report + 1] = item("warn", "Diagnostic file error: " .. diagnostics.file_error)
  end

  return report
end

---Render :checkhealth fimloom output through vim.health.
function M.check()
  vim.health.start("FIMLoom.nvim")
  for _, result in ipairs(M.collect()) do
    if result.advice then
      vim.health[result.level](result.message, result.advice)
    else
      vim.health[result.level](result.message)
    end
  end
end

return M
