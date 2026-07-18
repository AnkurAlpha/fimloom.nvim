local tests = {}

local function test(name, callback)
  tests[#tests + 1] = {
    name = name,
    callback = callback,
  }
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    local default_message =
      string.format("expected %s, received %s", vim.inspect(expected), vim.inspect(actual))
    error(message or default_message)
  end
end

test("plugin entry point loads once", function()
  assert_equal(vim.g.loaded_fimloom, 1)
  dofile(vim.fn.fnamemodify("plugin/fimloom.lua", ":p"))
  assert_equal(vim.g.loaded_fimloom, 1)
end)

test("Lua module exposes the initial public API", function()
  local fimloom = require("fimloom")

  assert_equal(type(fimloom.setup), "function")
  assert_equal(type(fimloom.is_configured), "function")
  assert_equal(type(fimloom.get_config), "function")
end)

test("setup accepts nil and tables", function()
  local fimloom = require("fimloom")

  assert_equal(fimloom.setup(), fimloom)
  assert_equal(fimloom.is_configured(), true)
  assert_equal(type(fimloom.get_config()), "table")
end)

test("setup keeps a defensive copy", function()
  local fimloom = require("fimloom")
  local options = { completion = { enabled = true } }

  fimloom.setup(options)
  options.completion.enabled = false

  local first_copy = fimloom.get_config()
  assert_equal(first_copy.completion.enabled, true)

  first_copy.completion.enabled = false
  assert_equal(fimloom.get_config().completion.enabled, true)
end)

test("setup rejects non-table options", function()
  local fimloom = require("fimloom")
  local ok, error_message = pcall(fimloom.setup, "invalid")

  assert_equal(ok, false)
  assert(error_message:find("expected a table or nil", 1, true), error_message)
end)

local failures = 0

for index, case in ipairs(tests) do
  local ok, error_message = pcall(case.callback)

  if ok then
    print(string.format("ok %d - %s", index, case.name))
  else
    failures = failures + 1
    local output = string.format("not ok %d - %s\n%s", index, case.name, error_message)
    vim.api.nvim_err_writeln(output)
  end
end

print(string.format("\n%d tests, %d failures", #tests, failures))

if failures > 0 then
  vim.cmd("cquit 1")
end
