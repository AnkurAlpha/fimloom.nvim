return function(t)
  t.test("plugin entry point loads once", function()
    t.assert_equal(vim.g.loaded_fimloom, 1)

    local plugin = vim.g.fimloom_test_root .. "/plugin/fimloom.lua"
    dofile(plugin)

    t.assert_equal(vim.g.loaded_fimloom, 1)
  end)

  t.test("Lua module exposes the configuration API", function()
    local fimloom = require("fimloom")

    t.assert_equal(type(fimloom.setup), "function")
    t.assert_equal(type(fimloom.is_configured), "function")
    t.assert_equal(type(fimloom.is_enabled), "function")
    t.assert_equal(type(fimloom.get_config), "function")
  end)

  t.test("setup resolves and stores configuration without side effects", function()
    local state = require("fimloom.state")
    local fimloom = require("fimloom")

    state._reset()
    t.assert_equal(fimloom.setup({ model = "qwen2.5-coder:3b" }), fimloom)
    t.assert_equal(fimloom.is_configured(), true)
    t.assert_equal(fimloom.is_enabled(), true)
    t.assert_equal(fimloom.get_config().model, "qwen2.5-coder:3b")
    t.assert_equal(state.snapshot().server.status, "unknown")
  end)

  t.test("setup rejects non-table options", function()
    local fimloom = require("fimloom")

    t.assert_error(function()
      fimloom.setup("invalid")
    end, "expected a table or nil")
  end)
end
