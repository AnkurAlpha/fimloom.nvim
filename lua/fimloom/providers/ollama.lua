local M = {
  name = "ollama",
  default_endpoint = "http://127.0.0.1:11434",
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
    error("fimloom.providers.ollama: context must be a table", 3)
  end

  if type(context.prefix) ~= "string" then
    error("fimloom.providers.ollama: context.prefix must be a string", 3)
  end

  if type(context.suffix) ~= "string" then
    error("fimloom.providers.ollama: context.suffix must be a string", 3)
  end
end

---Build an Ollama model-discovery request used as a readiness check.
---@param config table
---@return table
function M.health_request(config)
  local request = transport_options(config)
  request.method = "GET"
  request.url = config.endpoint .. "/api/tags"
  return request
end

---Build a non-streaming Ollama fill-in-the-middle request.
---@param context table
---@param config table
---@return table
function M.completion_request(context, config)
  validate_context(context)

  if type(config.model) ~= "string" or config.model:match("^%s*$") then
    error("fimloom.providers.ollama: model must be configured before requesting completion", 2)
  end

  local request = transport_options(config)
  request.method = "POST"
  request.url = config.endpoint .. "/api/generate"
  request.body = {
    model = config.model,
    prompt = context.prefix,
    suffix = context.suffix,
    stream = false,
    options = {
      num_predict = config.completion.generation.max_tokens,
      temperature = config.completion.generation.temperature,
    },
  }
  return request
end

---Interpret an Ollama /api/tags response.
---@param response table
---@param config table
---@return table? result
---@return string? error_message
function M.parse_health(response, config)
  if type(response) ~= "table" or type(response.models) ~= "table" then
    return nil, "Ollama /api/tags response did not contain a models list"
  end

  local result = {
    ready = true,
    model_available = nil,
  }

  if config.model then
    result.model_available = false
    for _, model in ipairs(response.models) do
      if type(model) == "table" and (model.name == config.model or model.model == config.model) then
        result.model_available = true
        break
      end
    end
  end

  return result
end

---Extract completion text from an Ollama /api/generate response.
---@param response table
---@return string? text
---@return string? error_message
function M.parse_completion(response)
  if type(response) ~= "table" or type(response.response) ~= "string" then
    return nil, "Ollama /api/generate response did not contain completion text"
  end

  return response.response
end

return M
