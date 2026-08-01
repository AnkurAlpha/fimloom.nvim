return function(t)
  local output = require("fimloom.output")

  t.test("output sanitizer trims only trailing blank lines by default", function()
    t.assert_equal(output.sanitize("value", ""), "value")
    t.assert_equal(output.sanitize("value\n", ""), "value")
    t.assert_equal(output.sanitize("value\n\n\n", ""), "value")
    t.assert_equal(output.sanitize("value\n  \n\t\n", ""), "value")
    t.assert_equal(output.sanitize("", ""), nil)
    t.assert_equal(output.sanitize(" \t\n  ", ""), nil)
  end)

  t.test("output sanitizer preserves internal blank lines and indentation", function()
    local completion = "function value()\n  local first = 1\n\n  return first\nend\n\n"
    t.assert_equal(
      output.sanitize(completion, ""),
      "function value()\n  local first = 1\n\n  return first\nend"
    )
    t.assert_equal(output.sanitize("\n  child()\n    nested()\n", ""), "\n  child()\n    nested()")
  end)

  t.test("trailing blank-line trimming remains configurable", function()
    t.assert_equal(
      output.sanitize("value\n\n", "", {
        max_bytes = 100,
        max_lines = 10,
        trim_trailing_blank_lines = false,
      }),
      "value\n\n"
    )
  end)
end
