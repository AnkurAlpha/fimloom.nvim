local config = require("fimloom.config")
local state = require("fimloom.state")

local M = {}

---Configure FIMLoom for the current Neovim instance.
---
---Configuration is resolved and stored without starting a model server or
---registering completion events. Those side effects are introduced in later
---implementation stages.
---@param options? table
---@return table module
function M.setup(options)
  local resolved = config.resolve(options)
  state.configure(resolved)

  return M
end

---Return whether setup has run successfully.
---@return boolean
function M.is_configured()
  return state.is_configured()
end

---Return whether FIMLoom is enabled.
---@return boolean
function M.is_enabled()
  return state.is_enabled()
end

---Return a defensive copy of the resolved configuration.
---@return table
function M.get_config()
  return state.get_config()
end

return M
