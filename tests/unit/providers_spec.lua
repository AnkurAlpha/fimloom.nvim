return function(t)
  local providers = require("fimloom.providers")

  t.test("built-in providers are listed deterministically", function()
    t.assert_deep_equal(providers.names(), { "llamacpp", "ollama" })
  end)

  t.test("provider lookup returns defensive copies", function()
    local first = providers.get("ollama")
    first.default_endpoint = "changed"

    t.assert_equal(providers.get("ollama").default_endpoint, "http://127.0.0.1:11434")
    t.assert_equal(providers.get("missing"), nil)
  end)
end
