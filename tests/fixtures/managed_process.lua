io.stdout:write("fimloom managed process stdout\n")
io.stdout:flush()
io.stderr:write("fimloom managed process stderr\n")
io.stderr:flush()

vim.wait(60000, function()
  return false
end, 1000)
