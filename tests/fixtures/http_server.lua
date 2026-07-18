local uv = vim.uv or vim.loop

local M = {}

local reasons = {
  [200] = "OK",
  [404] = "Not Found",
  [503] = "Service Unavailable",
}

local function parse_request(raw)
  local header_end = raw:find("\r\n\r\n", 1, true)
  if not header_end then
    return nil
  end

  local head = raw:sub(1, header_end - 1)
  local body = raw:sub(header_end + 4)
  local method, path = head:match("^(%u+)%s+([^%s]+)%s+HTTP/")
  local headers = {}

  for line in head:gmatch("[^\r\n]+") do
    local name, value = line:match("^([^:]+):%s*(.*)$")
    if name then
      headers[name:lower()] = value
    end
  end

  local content_length = tonumber(headers["content-length"] or "0")
  if #body < content_length then
    return nil
  end

  return {
    method = method,
    path = path,
    headers = headers,
    body = body:sub(1, content_length),
  }
end

local function response_for(request)
  if request.path == "/ok" then
    return 200, vim.json.encode({ message = "ok" }), 0
  end

  if request.path == "/echo" then
    return 200, request.body, 0
  end

  if request.path == "/bad-json" then
    return 200, "this is not JSON", 0
  end

  if request.path == "/error" then
    return 503, vim.json.encode({ error = "unavailable" }), 0
  end

  if request.path == "/large" then
    return 200, vim.json.encode({ data = string.rep("x", 16 * 1024) }), 0
  end

  if request.path == "/slow" then
    return 200, vim.json.encode({ message = "slow" }), 250
  end

  return 404, vim.json.encode({ error = "not found" }), 0
end

---Start a loopback HTTP server for integration tests.
---@param handler? fun(request: table): integer, string, integer?
---@return table server
function M.start(handler)
  local handle = assert(uv.new_tcp())
  local clients = {}
  local timers = {}
  local requests = {}

  handle:bind("127.0.0.1", 0)
  local address = handle:getsockname()

  local function close_client(client)
    clients[client] = nil
    if not client:is_closing() then
      pcall(client.read_stop, client)
      client:close()
    end
  end

  local function write_response(client, status, body)
    if client:is_closing() then
      return
    end

    local response = table.concat({
      string.format("HTTP/1.1 %d %s\r\n", status, reasons[status] or "Unknown"),
      "Content-Type: application/json\r\n",
      string.format("Content-Length: %d\r\n", #body),
      "Connection: close\r\n",
      "\r\n",
      body,
    })

    client:write(response, function()
      close_client(client)
    end)
  end

  local function dispatch(client, request)
    local status, body, delay_ms
    if handler then
      status, body, delay_ms = handler(request)
    else
      status, body, delay_ms = response_for(request)
    end

    delay_ms = delay_ms or 0
    if delay_ms == 0 then
      write_response(client, status, body)
      return
    end

    local timer = assert(uv.new_timer())
    timers[timer] = true
    timer:start(delay_ms, 0, function()
      timers[timer] = nil
      timer:stop()
      timer:close()
      write_response(client, status, body)
    end)
  end

  handle:listen(128, function(listen_error)
    assert(not listen_error, listen_error)

    local client = assert(uv.new_tcp())
    handle:accept(client)
    clients[client] = true
    local buffer = ""
    local handled = false

    client:read_start(function(read_error, data)
      if read_error then
        close_client(client)
        return
      end

      if not data then
        if not handled then
          close_client(client)
        end
        return
      end

      buffer = buffer .. data
      local request = parse_request(buffer)
      if not request or handled then
        return
      end

      handled = true
      client:read_stop()
      requests[#requests + 1] = request
      dispatch(client, request)
    end)
  end)

  local server = {
    url = string.format("http://127.0.0.1:%d", address.port),
    requests = requests,
  }

  function server.stop()
    for timer in pairs(timers) do
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end

    for client in pairs(clients) do
      close_client(client)
    end

    if not handle:is_closing() then
      handle:close()
    end
  end

  return server
end

return M
