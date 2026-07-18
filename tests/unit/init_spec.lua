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
    t.assert_equal(type(fimloom.enable), "function")
    t.assert_equal(type(fimloom.disable), "function")
    t.assert_equal(type(fimloom.complete), "function")
    t.assert_equal(type(fimloom.accept), "function")
    t.assert_equal(type(fimloom.dismiss), "function")
  end)

  t.test("setup resolves configuration and initializes inline completion", function()
    local completion = require("fimloom.completion")
    local state = require("fimloom.state")
    local fimloom = require("fimloom")

    state._reset()
    t.assert_equal(fimloom.setup({ model = "qwen2.5-coder:3b" }), fimloom)
    t.assert_equal(fimloom.is_configured(), true)
    t.assert_equal(fimloom.is_enabled(), true)
    t.assert_equal(fimloom.get_config().model, "qwen2.5-coder:3b")
    t.assert_equal(state.snapshot().server.owned, false)
    t.assert_equal(completion.status().configured, true)

    fimloom.disable()
    t.assert_equal(fimloom.is_enabled(), false)
    t.assert_equal(completion.status().configured, false)
    t.assert_equal(state.snapshot().server.status, "stopped")
  end)

  t.test("disabled setup can be enabled later", function()
    local completion = require("fimloom.completion")
    local state = require("fimloom.state")
    local fimloom = require("fimloom")

    state._reset()
    fimloom.setup({ enabled = false, model = "local-coder" })
    t.assert_equal(fimloom.is_enabled(), false)
    t.assert_equal(completion.status().configured, false)

    fimloom.enable()
    t.assert_equal(fimloom.is_enabled(), true)
    t.assert_equal(completion.status().configured, true)
    fimloom.disable()
  end)

  t.test("setup rejects non-table options", function()
    local fimloom = require("fimloom")

    t.assert_error(function()
      fimloom.setup("invalid")
    end, "expected a table or nil")
  end)
end
