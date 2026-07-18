local M = {}

local STATUS_MARKER = "\n__FIMLOOM_HTTP_STATUS__:"
local STDERR_LIMIT = 64 * 1024

local function new_error(kind, message, extra)
  local result = {
    ok = false,
    error = {
      kind = kind,
      message = message,
    },
  }

  if extra then
    for key, value in pairs(extra) do
      result[key] = value
    end
  end

  return result
end

local function validate_positive_integer(name, value)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 then
    error(string.format("fimloom.transport: %s must be a positive integer", name), 3)
  end
end

local function validate_options(options, callback)
  if type(options) ~= "table" then
    error("fimloom.transport.request: expected an options table", 3)
  end

  if type(callback) ~= "function" then
    error("fimloom.transport.request: expected a callback function", 3)
  end

  if type(options.url) ~= "string" or not options.url:match("^https?://") then
    error("fimloom.transport.request: url must be an HTTP or HTTPS URL", 3)
  end

  local method = options.method or (options.body == nil and "GET" or "POST")
  if type(method) ~= "string" or not method:match("^[A-Z]+$") then
    error("fimloom.transport.request: method must contain uppercase ASCII letters", 3)
  end

  if options.headers ~= nil and type(options.headers) ~= "table" then
    error("fimloom.transport.request: headers must be a table or nil", 3)
  end

  validate_positive_integer("connect_timeout_ms", options.connect_timeout_ms or 1000)
  validate_positive_integer("request_timeout_ms", options.request_timeout_ms or 15000)
  validate_positive_integer("max_response_bytes", options.max_response_bytes or 1024 * 1024)
end

local function encode_body(body)
  if body == nil then
    return nil
  end

  if type(body) == "string" then
    return body
  end

  if type(body) ~= "table" then
    error("fimloom.transport.request: body must be a table, string, or nil", 3)
  end

  local ok, encoded = pcall(vim.json.encode, body)
  if not ok then
    error(string.format("fimloom.transport.request: could not encode JSON body: %s", encoded), 3)
  end

  return encoded
end

local function normalized_headers(headers, has_body)
  local normalized = {
    ["Accept"] = "application/json",
  }
  local content_type_present = false

  for name, value in pairs(headers or {}) do
    if type(name) ~= "string" or type(value) ~= "string" then
      error("fimloom.transport.request: header names and values must be strings", 3)
    end

    if name:find("[\r\n]") or value:find("[\r\n]") then
      error("fimloom.transport.request: headers must not contain newlines", 3)
    end

    normalized[name] = value
    if name:lower() == "content-type" then
      content_type_present = true
    end
  end

  if has_body and not content_type_present then
    normalized["Content-Type"] = "application/json"
  end

  return normalized
end

local function seconds(milliseconds)
  return string.format("%.3f", milliseconds / 1000)
end

local function build_command(options, payload)
  local connect_timeout_ms = options.connect_timeout_ms or 1000
  local request_timeout_ms = options.request_timeout_ms or 15000
  local method = options.method or (payload == nil and "GET" or "POST")
  local headers = normalized_headers(options.headers, payload ~= nil)
  local header_names = vim.tbl_keys(headers)
  table.sort(header_names)

  local command = {
    "curl",
    "--silent",
    "--show-error",
    "--proto",
    "=http,https",
    "--request",
    method,
    "--connect-timeout",
    seconds(connect_timeout_ms),
    "--max-time",
    seconds(request_timeout_ms),
  }

  for _, name in ipairs(header_names) do
    command[#command + 1] = "--header"
    command[#command + 1] = string.format("%s: %s", name, headers[name])
  end

  if payload ~= nil then
    command[#command + 1] = "--data-binary"
    command[#command + 1] = "@-"
  end

  command[#command + 1] = "--write-out"
  command[#command + 1] = STATUS_MARKER .. "%{http_code}"
  command[#command + 1] = "--url"
  command[#command + 1] = options.url

  return command
end

local function append_bounded(chunks, current_size, data, limit)
  if not data or data == "" or current_size >= limit then
    return current_size
  end

  local remaining = limit - current_size
  local chunk = #data > remaining and data:sub(1, remaining) or data
  chunks[#chunks + 1] = chunk
  return current_size + #chunk
end

local function split_status(output)
  local marker_start
  local search_from = 1

  while true do
    local found = output:find(STATUS_MARKER, search_from, true)
    if not found then
      break
    end

    marker_start = found
    search_from = found + 1
  end

  if not marker_start then
    return nil, nil
  end

  local status_text = output:sub(marker_start + #STATUS_MARKER)
  if not status_text:match("^%d%d%d$") then
    return nil, nil
  end

  return output:sub(1, marker_start - 1), tonumber(status_text)
end

local function decode_json(body)
  if body == "" then
    return true, nil
  end

  return pcall(vim.json.decode, body)
end

local function process_response(output, max_response_bytes, decode_response)
  local body, status = split_status(output)
  if not body or not status then
    return new_error("protocol", "curl response did not contain an HTTP status marker")
  end

  if #body > max_response_bytes then
    return new_error("response_too_large", "HTTP response exceeded the configured byte limit", {
      status = status,
    })
  end

  local decoded_ok, decoded = decode_json(body)

  if status < 200 or status >= 300 then
    return new_error("http", string.format("HTTP request failed with status %d", status), {
      status = status,
      body = body,
      json = decoded_ok and decoded or nil,
    })
  end

  if decode_response and not decoded_ok then
    return new_error("decode", "HTTP response was not valid JSON", {
      status = status,
      body = body,
    })
  end

  return {
    ok = true,
    status = status,
    body = body,
    json = decode_response and decoded or nil,
  }
end

local function process_message(completed, stderr)
  local message = stderr:gsub("^%s+", ""):gsub("%s+$", "")
  if message ~= "" then
    return message
  end

  return string.format("curl exited with code %d and signal %d", completed.code, completed.signal)
end

---Send an asynchronous JSON HTTP request through curl.
---@param options table
---@param callback fun(result: table)
---@return table request
function M.request(options, callback)
  validate_options(options, callback)

  local payload = encode_body(options.body)
  local command = build_command(options, payload)
  local max_response_bytes = options.max_response_bytes or 1024 * 1024
  local request_timeout_ms = options.request_timeout_ms or 15000
  local decode_response = options.decode_json ~= false
  local stdout_limit = max_response_bytes + #STATUS_MARKER + 3
  local stdout_chunks = {}
  local stderr_chunks = {}
  local stdout_size = 0
  local stderr_size = 0
  local stdout_error

  local request = {
    _cancelled = false,
    _done = false,
    _process = nil,
    _too_large = false,
  }

  local function kill_process()
    if request._process and not request._done then
      pcall(request._process.kill, request._process, 15)
    end
  end

  local function finish(result)
    if request._done then
      return
    end

    request._done = true
    request._process = nil
    vim.schedule(function()
      callback(result)
    end)
  end

  function request:cancel()
    if self._done then
      return false
    end

    self._cancelled = true
    kill_process()
    return true
  end

  function request:is_done()
    return self._done
  end

  local system_options = {
    text = true,
    timeout = request_timeout_ms + 250,
    stdout = function(error_message, data)
      if error_message then
        stdout_error = error_message
      end

      if not data then
        return
      end

      if stdout_size + #data > stdout_limit then
        request._too_large = true
      end

      stdout_size = append_bounded(stdout_chunks, stdout_size, data, stdout_limit)

      if request._too_large then
        kill_process()
      end
    end,
    stderr = function(_, data)
      stderr_size = append_bounded(stderr_chunks, stderr_size, data, STDERR_LIMIT)
    end,
  }

  if payload ~= nil then
    system_options.stdin = payload
  end

  local started, process_or_error = pcall(vim.system, command, system_options, function(completed)
    local stderr = table.concat(stderr_chunks)

    if request._cancelled then
      finish(new_error("cancelled", "HTTP request was cancelled"))
      return
    end

    if request._too_large then
      finish(new_error("response_too_large", "HTTP response exceeded the configured byte limit"))
      return
    end

    if stdout_error then
      finish(new_error("io", string.format("could not read curl output: %s", stdout_error)))
      return
    end

    if completed.code ~= 0 then
      local timed_out = completed.code == 28 or completed.signal == 15
      local kind = timed_out and "timeout" or "process"
      if completed.code == 6 or completed.code == 7 then
        kind = "connection"
      end

      finish(new_error(kind, process_message(completed, stderr), {
        code = completed.code,
        signal = completed.signal,
      }))
      return
    end

    local output = table.concat(stdout_chunks)
    finish(process_response(output, max_response_bytes, decode_response))
  end)

  if not started then
    finish(new_error("spawn", string.format("could not start curl: %s", process_or_error)))
    return request
  end

  request._process = process_or_error
  if request._cancelled or request._too_large then
    kill_process()
  end

  return request
end

return M
