local M = {}

local server_statuses = {
  unknown = true,
  starting = true,
  ready = true,
  stopped = true,
  failed = true,
}

local function initial_server_state()
  return {
    status = "unknown",
    owned = false,
    stdout_tail = "",
    stderr_tail = "",
  }
end

local function initial_state()
  return {
    configured = false,
    enabled = false,
    shutting_down = false,
    config = nil,
    request_seq = 0,
    server = initial_server_state(),
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
  runtime.shutting_down = false
  runtime.server = initial_server_state()
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

---Replace serializable server lifecycle metadata.
---@param server table
function M.set_server(server)
  if type(server) ~= "table" then
    error("fimloom.state.set_server: expected a server state table", 2)
  end

  if not server_statuses[server.status] then
    error("fimloom.state.set_server: unknown server status", 2)
  end

  if type(server.owned) ~= "boolean" then
    error("fimloom.state.set_server: server.owned must be a boolean", 2)
  end

  runtime.server = vim.deepcopy(server)
end

---Return a defensive copy of server lifecycle metadata.
---@return table
function M.get_server()
  return vim.deepcopy(runtime.server)
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
