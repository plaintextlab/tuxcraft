-- Options on top of LazyVim's defaults (https://lazyvim.org/configuration/general).
local opt = vim.opt
opt.relativenumber = false -- plain line numbers, like VS Code
opt.wrap = false
opt.scrolloff = 8
opt.mousemoveevent = true -- hover in the file tree and tabs
vim.g.lazyvim_picker = "snacks"
