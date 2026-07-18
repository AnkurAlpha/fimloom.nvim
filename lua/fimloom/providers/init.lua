local M = {}

local registry = {
  ollama = {
    name = "ollama",
    default_endpoint = "http://127.0.0.1:11434",
  },
  llamacpp = {
    name = "llamacpp",
    default_endpoint = "http://127.0.0.1:8012",
  },
}

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
end

---Register provider metadata for configuration resolution.
---@param provider table
function M.register(provider)
  validate_provider(provider)

  if registry[provider.name] then
    error(string.format("fimloom.providers.register: provider %q already exists", provider.name), 2)
  end

  registry[provider.name] = vim.deepcopy(provider)
end

---Return provider metadata or nil when no provider is registered.
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

return M
