-- VS Code keys, added to LazyVim's own (Space opens the full menu; :Keymaps or Space s k lists all).
local map = vim.keymap.set

-- Find / palette
map("n", "<C-p>", function() Snacks.picker.files() end, { desc = "Find file (Ctrl+P)" })
map({ "n", "i" }, "<F1>", function() Snacks.picker.commands() end, { desc = "Command palette (F1)" })
map("n", "<C-S-p>", function() Snacks.picker.commands() end, { desc = "Command palette" })
map("n", "<C-S-f>", function() Snacks.picker.grep() end, { desc = "Search in files (Ctrl+Shift+F)" })
map("n", "<C-b>", function() Snacks.explorer() end, { desc = "Toggle file explorer (Ctrl+B)" })

-- Editing
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment (Ctrl+/)" })
map("x", "<C-/>", "gc", { remap = true, desc = "Toggle comment (Ctrl+/)" })
map("i", "<C-/>", "<Esc>gcca", { remap = true, desc = "Toggle comment (Ctrl+/)" })
map("n", "<C-_>", "gcc", { remap = true, desc = "which_key_ignore" }) -- terminals sending Ctrl+/ as Ctrl+_
map("x", "<C-_>", "gc", { remap = true, desc = "which_key_ignore" })
map({ "n", "i", "v" }, "<A-Up>", "<A-k>", { remap = true, desc = "Move line up (Alt+Up)" })
map({ "n", "i", "v" }, "<A-Down>", "<A-j>", { remap = true, desc = "Move line down (Alt+Down)" })
map("n", "<C-a>", "ggVG", { desc = "Select all" })
map({ "n", "i" }, "<A-S-f>", function() LazyVim.format({ force = true }) end, { desc = "Format (Shift+Alt+F)" })

-- Code (LSP)
map("n", "<F2>", vim.lsp.buf.rename, { desc = "Rename symbol (F2)" })
map("n", "<F12>", vim.lsp.buf.definition, { desc = "Go to definition (F12)" })
map({ "n", "x" }, "<C-.>", vim.lsp.buf.code_action, { desc = "Quick fix (Ctrl+.)" })

-- Tabs (buffers) and terminal
map("n", "<C-Tab>", "<cmd>bnext<cr>", { desc = "Next tab (Ctrl+Tab)" })
map("n", "<C-S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous tab" })
map({ "n", "t" }, "<C-`>", function() Snacks.terminal() end, { desc = "Terminal (Ctrl+`)" })
