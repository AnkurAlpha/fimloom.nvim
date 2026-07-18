local config = require("fimloom.config")
local completion = require("fimloom.completion")
local process = require("fimloom.process")
local state = require("fimloom.state")

local M = {}

---Configure FIMLoom for the current Neovim instance.
---@param options? table
---@return table module
function M.setup(options)
  local resolved = config.resolve(options)

  completion.shutdown()
  process.shutdown()
  state.configure(resolved)

  if resolved.enabled then
    completion.setup(resolved)
  end
  process.setup(resolved)

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

---Enable inline completion after setup.
function M.enable()
  if not state.is_configured() then
    error("fimloom.enable: setup must be called first", 2)
  end

  state.set_enabled(true)
  local resolved = state.get_config()
  completion.setup(resolved)
  process.setup(resolved)
end

---Disable inline completion and clear pending work.
function M.disable()
  completion.shutdown()
  process.shutdown()
  if state.is_configured() then
    state.set_enabled(false)
  end
end

---Request an inline completion without waiting for the debounce timer.
---@return boolean started
---@return string? reason
function M.complete()
  return completion.trigger({ manual = true })
end

---Accept the currently displayed inline suggestion.
---@return boolean accepted
function M.accept()
  return completion.accept()
end

---Dismiss the currently displayed suggestion and pending work.
---@return boolean dismissed
function M.dismiss()
  return completion.dismiss()
end

return M
