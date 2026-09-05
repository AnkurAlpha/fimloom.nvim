local log = require("fimloom.log")
local providers_module = require("fimloom.providers")
local state = require("fimloom.state")

local M = {}

local OUTPUT_LIMIT = 64 * 1024

local default_dependencies = {
  providers = providers_module,
  defer_fn = vim.defer_fn,
  schedule = vim.schedule,
  jobstart = function(command, options)
    return vim.fn.jobstart(command, options)
  end,
  jobstop = function(job_id)
    return vim.fn.jobstop(job_id)
  end,
  jobpid = function(job_id)
    return vim.fn.jobpid(job_id)
  end,
}

local dependencies = default_dependencies
local runtime_config
local generation = 0
local active_health
local poll_timer
local deadline_timer
local augroup
local job_id
local pid
local owned = false
local started_command
local stdout_tail = ""
local stderr_tail = ""
local exit_code
local last_error

local function append_tail(current, data)
  if type(data) ~= "table" or #data == 0 then
    return current
  end

  local chunk = table.concat(data, "\n")
  if chunk == "" then
    return current
  end

  local combined = current .. chunk
  if #combined > OUTPUT_LIMIT then
    combined = combined:sub(#combined - OUTPUT_LIMIT + 1)
  end
  return combined
end

local function publish(status)
  local server = {
    status = status,
    owned = owned,
    stdout_tail = stdout_tail,
    stderr_tail = stderr_tail,
  }

  if job_id then
    server.job_id = job_id
  end
  if pid then
    server.pid = pid
  end
  if started_command then
    server.started_command = vim.deepcopy(started_command)
  end
  if exit_code ~= nil then
    server.exit_code = exit_code
  end
  if last_error then
    server.error = vim.deepcopy(last_error)
  end

  state.set_server(server)
end

local function close_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function cancel_timers()
  close_timer(poll_timer)
  close_timer(deadline_timer)
  poll_timer = nil
  deadline_timer = nil
end

local function cancel_health()
  local record = active_health
  active_health = nil
  if record and record.handle and type(record.handle.cancel) == "function" then
    pcall(record.handle.cancel, record.handle)
  end
end

local function cancel_async()
  cancel_timers()
  cancel_health()
end

local function error_message(result)
  if result and result.error and type(result.error.message) == "string" then
    return result.error.message
  end
  return "the configured provider endpoint is not ready"
end

local function endpoint_responded(result)
  if type(result) ~= "table" then
    return false
  end

  if result.ok == true then
    return true
  end

  return type(result.status) == "number" and result.status >= 100 and result.status <= 599
end

local function validate_resolved_command(command)
  local is_list = vim.islist or vim.tbl_islist
  if type(command) ~= "table" or not is_list(command) or #command == 0 then
    return nil, "server.command must resolve to a non-empty argument list"
  end

  local resolved = {}
  for index, argument in ipairs(command) do
    if type(argument) ~= "string" or argument:match("^%s*$") then
      return nil, string.format("server.command[%d] must be a non-empty string", index)
    end
    resolved[index] = argument
  end

  return resolved
end

local function resolve_command()
  local command = runtime_config.server.command
  if type(command) == "function" then
    local ok, result = pcall(command, vim.deepcopy(runtime_config))
    if not ok then
      return nil, string.format("server.command failed: %s", result)
    end
    command = result
  end

  return validate_resolved_command(command)
end

local function stop_owned_job()
  local stopped_job = job_id
  local should_stop = owned and stopped_job ~= nil
  job_id = nil
  pid = nil
  owned = false

  if should_stop then
    pcall(dependencies.jobstop, stopped_job)
  end

  return should_stop
end

local function fail_owned(kind, message)
  generation = generation + 1
  cancel_async()
  stop_owned_job()
  last_error = {
    kind = kind,
    message = message,
  }
  publish("failed")
  log.notify("server:" .. kind, string.format("FIMLoom server failed: %s", message), "warn")
end

local probe_health

local function schedule_poll(token)
  if generation ~= token or poll_timer then
    return
  end

  local timer
  timer = dependencies.defer_fn(function()
    if generation ~= token or poll_timer ~= timer then
      return
    end

    poll_timer = nil
    probe_health(token, false)
  end, runtime_config.server.startup_poll_interval_ms)
  poll_timer = timer
end

local function schedule_deadline(token)
  if generation ~= token or deadline_timer then
    return
  end

  local timer
  timer = dependencies.defer_fn(function()
    if generation ~= token or deadline_timer ~= timer then
      return
    end

    deadline_timer = nil
    fail_owned(
      "startup_timeout",
      string.format(
        "server did not become ready within %d ms",
        runtime_config.server.startup_timeout_ms
      )
    )
  end, runtime_config.server.startup_timeout_ms)
  deadline_timer = timer
end

local function mark_ready(token)
  if generation ~= token then
    return
  end

  cancel_timers()
  last_error = nil
  exit_code = nil
  publish("ready")
  log.write("info", "server_ready", {
    provider = runtime_config.provider,
    endpoint = runtime_config.endpoint,
    owned = owned,
    pid = pid,
  })
end

local function on_job_exit(token, exited_job, code)
  dependencies.schedule(function()
    if generation ~= token or job_id ~= exited_job then
      return
    end

    generation = generation + 1
    cancel_async()
    job_id = nil
    pid = nil
    owned = false
    exit_code = code
    last_error = {
      kind = "process_exit",
      message = string.format("managed server process exited with code %d", code),
    }
    publish("failed")
    log.notify(
      "server:process_exit",
      string.format("FIMLoom server process exited with code %d", code),
      "warn"
    )
  end)
end

local function start_job(token)
  local command, command_error = resolve_command()
  if not command then
    fail_owned("command", command_error)
    return
  end

  started_command = command
  local options = {
    detach = not runtime_config.server.auto_stop,
    stdin = "null",
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(callback_job, data)
      if generation ~= token or job_id ~= callback_job then
        return
      end
      stdout_tail = append_tail(stdout_tail, data)
      publish(state.get_server().status)
    end,
    on_stderr = function(callback_job, data)
      if generation ~= token or job_id ~= callback_job then
        return
      end
      stderr_tail = append_tail(stderr_tail, data)
      publish(state.get_server().status)
    end,
    on_exit = function(callback_job, code)
      on_job_exit(token, callback_job, code)
    end,
  }

  local ok, started_job = pcall(dependencies.jobstart, command, options)
  if not ok or type(started_job) ~= "number" or started_job <= 0 then
    fail_owned("spawn", string.format("could not start server command: %s", tostring(started_job)))
    return
  end

  job_id = started_job
  owned = true
  local pid_ok, process_id = pcall(dependencies.jobpid, started_job)
  if pid_ok and type(process_id) == "number" and process_id > 0 then
    pid = process_id
  end
  publish("starting")
  log.write("info", "server_started", {
    provider = runtime_config.provider,
    endpoint = runtime_config.endpoint,
    pid = pid,
  })

  schedule_deadline(token)

  probe_health(token, false)
end

local function handle_health(token, initial, result)
  if generation ~= token then
    return
  end

  if result and result.ok and result.ready then
    mark_ready(token)
    return
  end

  if initial then
    if endpoint_responded(result) then
      -- An HTTP response proves that something already owns the endpoint.
      -- llama.cpp returns 503 while its model is loading; never launch a
      -- second server merely because that existing service is not ready yet.
      schedule_deadline(token)
      schedule_poll(token)
      log.write("debug", "server_external_wait", {
        provider = runtime_config.provider,
        endpoint = runtime_config.endpoint,
        status = result.status,
      })
      return
    end

    if runtime_config.server.auto_start then
      start_job(token)
    else
      last_error = {
        kind = "unavailable",
        message = error_message(result),
      }
      publish("failed")
      log.notify(
        "server:unavailable",
        string.format("FIMLoom server is unavailable: %s", last_error.message),
        "warn"
      )
    end
    return
  end

  schedule_poll(token)
end

probe_health = function(token, initial)
  if generation ~= token or active_health then
    return
  end

  local record = {
    done = false,
    handle = nil,
  }
  active_health = record

  local ok, handle_or_error = pcall(dependencies.providers.health, runtime_config, function(result)
    record.done = true
    if active_health == record then
      active_health = nil
    end
    handle_health(token, initial, result)
  end)

  if not ok then
    if active_health == record then
      active_health = nil
    end
    handle_health(token, initial, {
      ok = false,
      error = {
        message = tostring(handle_or_error),
      },
    })
    return
  end

  record.handle = handle_or_error
  if record.done and active_health == record then
    active_health = nil
  end
end

local function register_autocmd()
  augroup = vim.api.nvim_create_augroup("FIMLoomProcess", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      if runtime_config and runtime_config.server.auto_stop then
        M.stop()
      end
    end,
    desc = "Stop the local inference server owned by FIMLoom",
  })
end

---Initialize server lifecycle management and probe provider readiness.
---@param config table
---@param injected? table Internal dependency overrides used by tests.
function M.setup(config, injected)
  if type(config) ~= "table" then
    error("fimloom.process.setup: expected a resolved configuration table", 2)
  end

  M.shutdown()
  dependencies = vim.tbl_extend("force", {}, default_dependencies, injected or {})
  runtime_config = vim.deepcopy(config)
  stdout_tail = ""
  stderr_tail = ""
  started_command = nil
  exit_code = nil
  last_error = nil
  publish("unknown")
  register_autocmd()

  if state.is_enabled() then
    M.start()
  else
    publish("stopped")
  end
end

---Probe readiness and start the configured command when necessary.
---@return boolean started
---@return string? reason
function M.start()
  if not runtime_config then
    return false, "FIMLoom server lifecycle is not configured"
  end

  local status = state.get_server().status
  if status == "starting" or status == "ready" then
    return false, string.format("server is already %s", status)
  end

  generation = generation + 1
  cancel_async()
  stop_owned_job()
  stdout_tail = ""
  stderr_tail = ""
  started_command = nil
  exit_code = nil
  last_error = nil
  publish("starting")

  local token = generation
  probe_health(token, true)
  log.write("debug", "server_probe_started", {
    provider = runtime_config.provider,
    endpoint = runtime_config.endpoint,
  })
  return true
end

---Stop only the server job started by this Neovim instance.
---@return boolean stopped
function M.stop()
  local had_work = active_health ~= nil or poll_timer ~= nil or deadline_timer ~= nil
  had_work = owned or had_work

  generation = generation + 1
  cancel_async()
  local stopped_job = stop_owned_job()
  last_error = nil
  exit_code = nil
  publish("stopped")
  if stopped_job or had_work then
    log.write("info", "server_stopped", {
      provider = runtime_config and runtime_config.provider or nil,
    })
  end
  return stopped_job or had_work
end

---Tear down lifecycle hooks and managed work. Safe to call repeatedly.
function M.shutdown()
  M.stop()

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end

  runtime_config = nil
  dependencies = default_dependencies
end

---Return serializable server lifecycle metadata.
---@return table
function M.status()
  return state.get_server()
end

---Return whether lifecycle setup has retained a resolved configuration.
---@return boolean
function M.is_configured()
  return runtime_config ~= nil
end

return M
