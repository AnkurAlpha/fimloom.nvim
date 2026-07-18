local transport = require("fimloom.transport")

local M = {}

local required_methods = {
  "health_request",
  "completion_request",
  "parse_health",
  "parse_completion",
}

local registry = {}

local function validate_provider(provider)
  if type(provider) ~= "table" then
    error("fimloom.providers.register: expected a provider table", 3)
  end

  if type(provider.name) ~= "string" or provider.name:match("^%s*$") then
    error("fimloom.providers.register: provider.name must be a non-empty string", 3)
  end

  if type(provider.default_endpoint) ~= "string" or provider.default_endpoint:match("^%s*$") then
    error("fimloom.providers.register: provider.default_endpoint must be a non-empty string", 3)
  end

  for _, method in ipairs(required_methods) do
    if type(provider[method]) ~= "function" then
      error(string.format("fimloom.providers.register: provider.%s must be a function", method), 3)
    end
  end
end

local function install(provider)
  validate_provider(provider)
  registry[provider.name] = vim.deepcopy(provider)
end

install(require("fimloom.providers.ollama"))
install(require("fimloom.providers.llamacpp"))

local function provider_error(provider, message, status)
  return {
    ok = false,
    status = status,
    error = {
      kind = "provider",
      message = string.format("%s: %s", provider.name, message),
    },
  }
end

local function validate_callback(operation, callback)
  if type(callback) ~= "function" then
    error(string.format("fimloom.providers.%s: expected a callback function", operation), 3)
  end
end

local function resolve_configured_provider(config, operation)
  if type(config) ~= "table" then
    error(
      string.format("fimloom.providers.%s: expected a resolved configuration table", operation),
      3
    )
  end

  local provider = registry[config.provider]
  if not provider then
    error(string.format("fimloom.providers.%s: unknown provider %q", operation, config.provider), 3)
  end

  return provider
end

local function failed_request(result, callback)
  local request = {
    _done = false,
  }

  function request:cancel()
    return false
  end

  function request:is_done()
    return self._done
  end

  vim.schedule(function()
    request._done = true
    callback(result)
  end)

  return request
end

local function build_request(provider, method, ...)
  local ok, request_or_error = pcall(provider[method], ...)
  if ok then
    return request_or_error
  end

  return nil, tostring(request_or_error)
end

---Register a provider adapter.
---@param provider table
function M.register(provider)
  validate_provider(provider)

  if registry[provider.name] then
    error(string.format("fimloom.providers.register: provider %q already exists", provider.name), 2)
  end

  install(provider)
end

---Return a defensive copy of a provider adapter.
---@param name string
---@return table?
function M.get(name)
  local provider = registry[name]
  return provider and vim.deepcopy(provider) or nil
end

---Return registered provider names in deterministic order.
---@return string[]
function M.names()
  local names = vim.tbl_keys(registry)
  table.sort(names)
  return names
end

---Check whether the configured provider is ready.
---@param config table
---@param callback fun(result: table)
---@return table request
function M.health(config, callback)
  validate_callback("health", callback)
  local provider = resolve_configured_provider(config, "health")
  local request, build_error = build_request(provider, "health_request", config)

  if not request then
    return failed_request(provider_error(provider, build_error), callback)
  end

  return transport.request(request, function(response)
    if not response.ok then
      callback(response)
      return
    end

    local parse_ok, result, parse_error = pcall(provider.parse_health, response.json, config)
    if not parse_ok then
      callback(provider_error(provider, tostring(result), response.status))
      return
    end

    if not result then
      callback(provider_error(provider, parse_error, response.status))
      return
    end

    result.ok = true
    result.provider = provider.name
    result.status = response.status
    callback(result)
  end)
end

---Request a fill-in-the-middle completion from the configured provider.
---@param context table
---@param config table
---@param callback fun(result: table)
---@return table request
function M.complete(context, config, callback)
  validate_callback("complete", callback)
  local provider = resolve_configured_provider(config, "complete")
  local request, build_error = build_request(provider, "completion_request", context, config)

  if not request then
    return failed_request(provider_error(provider, build_error), callback)
  end

  return transport.request(request, function(response)
    if not response.ok then
      callback(response)
      return
    end

    local parse_ok, text, parse_error = pcall(provider.parse_completion, response.json)
    if not parse_ok then
      callback(provider_error(provider, tostring(text), response.status))
      return
    end

    if not text then
      callback(provider_error(provider, parse_error, response.status))
      return
    end

    callback({
      ok = true,
      provider = provider.name,
      status = response.status,
      text = text,
    })
  end)
end

return M
