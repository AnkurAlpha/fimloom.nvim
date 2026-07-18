local source = debug.getinfo(1, "S").source
local path = source:sub(1, 1) == "@" and source:sub(2) or source
local tests_dir = vim.fn.fnamemodify(path, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h")

vim.g.fimloom_test_root = root
vim.opt.runtimepath:prepend(root)
vim.o.loadplugins = true

package.path = table.concat({ root .. "/?.lua", root .. "/?/init.lua", package.path }, ";")
