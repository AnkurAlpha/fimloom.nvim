local M = {}

local configured = false
local resolved_options = {}

---Configure FIMLoom for the current Neovim instance.
---
---Stage 1 intentionally stores configuration without starting a model server
---or registering completion events. Validation and defaults are introduced in
---the next implementation stage.
---@param options? table
---@return table module
function M.setup(options)
  options = options or {}

  if type(options) ~= "table" then
    error("fimloom.setup: expected a table or nil", 2)
  end

  resolved_options = vim.deepcopy(options)
  configured = true

  return M
end

---Return whether setup has run successfully.
---@return boolean
function M.is_configured()
  return configured
end

---Return a defensive copy of the currently stored options.
---@return table
function M.get_config()
  return vim.deepcopy(resolved_options)
end

return M
