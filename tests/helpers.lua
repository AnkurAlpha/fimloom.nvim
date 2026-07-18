local M = {
  cases = {},
}

function M.test(name, callback)
  M.cases[#M.cases + 1] = {
    name = name,
    callback = callback,
  }
end

function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    local default_message =
      string.format("expected %s, received %s", vim.inspect(expected), vim.inspect(actual))
    error(message or default_message, 2)
  end
end

function M.assert_deep_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    local default_message =
      string.format("expected %s, received %s", vim.inspect(expected), vim.inspect(actual))
    error(message or default_message, 2)
  end
end

function M.assert_error(callback, expected_fragment)
  local ok, error_message = pcall(callback)

  M.assert_equal(ok, false, "expected callback to raise an error")
  assert(error_message:find(expected_fragment, 1, true), error_message)
end

function M.run()
  local failures = 0

  for index, case in ipairs(M.cases) do
    local ok, error_message = pcall(case.callback)

    if ok then
      print(string.format("ok %d - %s", index, case.name))
    else
      failures = failures + 1
      local output = string.format("not ok %d - %s\n%s", index, case.name, error_message)
      vim.api.nvim_err_writeln(output)
    end
  end

  print(string.format("\n%d tests, %d failures", #M.cases, failures))

  if failures > 0 then
    vim.cmd("cquit 1")
  end
end

return M
