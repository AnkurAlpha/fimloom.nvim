local config = require("fimloom.config")
local completion = require("fimloom.completion")
local log = require("fimloom.log")
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
  log.setup(resolved)

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

---Toggle inline completion after setup.
---@return boolean enabled
function M.toggle()
  if state.is_enabled() then
    M.disable()
    return false
  end

  M.enable()
  return true
end

---Probe readiness and start the configured local server when needed.
---@return boolean started
---@return string? reason
function M.start()
  if state.is_configured() and not process.is_configured() then
    process.setup(state.get_config())
  end
  return process.start()
end

---Stop only a local server process owned by this Neovim instance.
---@return boolean stopped
function M.stop()
  return process.stop()
end

---Return privacy-safe runtime status metadata.
---@return table
function M.status()
  local server = state.get_server()
  local result = {
    configured = state.is_configured(),
    enabled = state.is_enabled(),
    server = {
      status = server.status,
      owned = server.owned,
      job_id = server.job_id,
      pid = server.pid,
      exit_code = server.exit_code,
      error_kind = server.error and server.error.kind or nil,
      stdout_bytes = #(server.stdout_tail or ""),
      stderr_bytes = #(server.stderr_tail or ""),
    },
    completion = completion.status(),
    diagnostics = log.status(),
  }

  if result.configured then
    local resolved = state.get_config()
    result.provider = resolved.provider
    result.endpoint = resolved.endpoint
    result.model = resolved.model
  end

  return result
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
