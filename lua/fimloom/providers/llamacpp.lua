local M = {
  name = "llamacpp",
  default_endpoint = "http://127.0.0.1:8012",
}

local function transport_options(config)
  return {
    connect_timeout_ms = config.transport.connect_timeout_ms,
    request_timeout_ms = config.transport.request_timeout_ms,
    max_response_bytes = config.transport.max_response_bytes,
  }
end

local function validate_context(context)
  if type(context) ~= "table" then
    error("fimloom.providers.llamacpp: context must be a table", 3)
  end

  if type(context.prefix) ~= "string" then
    error("fimloom.providers.llamacpp: context.prefix must be a string", 3)
  end

  if type(context.suffix) ~= "string" then
    error("fimloom.providers.llamacpp: context.suffix must be a string", 3)
  end
end

---Build a llama.cpp readiness request.
---@param config table
---@return table
function M.health_request(config)
  local request = transport_options(config)
  request.method = "GET"
  request.url = config.endpoint .. "/health"
  return request
end

---Build a non-streaming llama.cpp fill-in-the-middle request.
---@param context table
---@param config table
---@return table
function M.completion_request(context, config)
  validate_context(context)

  local request = transport_options(config)
  request.method = "POST"
  request.url = config.endpoint .. "/infill"
  request.body = {
    input_prefix = context.prefix,
    input_suffix = context.suffix,
    stream = false,
    cache_prompt = true,
    n_predict = config.completion.generation.max_tokens,
    temperature = config.completion.generation.temperature,
  }
  return request
end

---Interpret a llama.cpp /health response.
---@param response table
---@return table? result
---@return string? error_message
function M.parse_health(response)
  if type(response) ~= "table" or response.status ~= "ok" then
    return nil, 'llama.cpp /health response did not report status "ok"'
  end

  return {
    ready = true,
  }
end

---Extract completion text from a llama.cpp /infill response.
---@param response table
---@return string? text
---@return string? error_message
function M.parse_completion(response)
  if type(response) ~= "table" or type(response.content) ~= "string" then
    return nil, "llama.cpp /infill response did not contain completion text"
  end

  return response.content
end

return M
