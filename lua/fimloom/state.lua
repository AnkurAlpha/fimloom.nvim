local M = {}

local function initial_state()
  return {
    configured = false,
    enabled = false,
    shutting_down = false,
    config = nil,
    request_seq = 0,
    server = {
      status = "unknown",
      owned = false,
    },
  }
end

local runtime = initial_state()

---Store a resolved configuration and enable the configured runtime.
---@param resolved table
function M.configure(resolved)
  if type(resolved) ~= "table" then
    error("fimloom.state.configure: expected a resolved configuration table", 2)
  end

  runtime.config = vim.deepcopy(resolved)
  runtime.configured = true
  runtime.enabled = resolved.enabled
end

---@return boolean
function M.is_configured()
  return runtime.configured
end

---@return boolean
function M.is_enabled()
  return runtime.enabled
end

---@param enabled boolean
function M.set_enabled(enabled)
  if type(enabled) ~= "boolean" then
    error("fimloom.state.set_enabled: expected a boolean", 2)
  end

  runtime.enabled = enabled
end

---Return a defensive copy of the resolved configuration.
---@return table
function M.get_config()
  return vim.deepcopy(runtime.config or {})
end

---Advance and return the request sequence.
---@return integer
function M.next_request_id()
  runtime.request_seq = runtime.request_seq + 1
  return runtime.request_seq
end

---Return a serializable snapshot for diagnostics and tests.
---@return table
function M.snapshot()
  return vim.deepcopy(runtime)
end

---Reset private runtime state. Intended for internal cleanup and tests.
function M._reset()
  runtime = initial_state()
end

return M
