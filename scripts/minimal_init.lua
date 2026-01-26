-- Minimal Neovim config for test isolation
local repo_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h:h')

-- Set up runtimepath
-- 1. Load dependencies from .deps/
vim.opt.runtimepath:prepend(repo_root .. '/.deps/mini.nvim')
-- 2. Load plugin from repo
vim.opt.runtimepath:prepend(repo_root)

-- Setup nvim options for testing
vim.opt.number = false
vim.opt.signcolumn = 'no'
vim.opt.swapfile = false
vim.opt.backup = false

-- Load mini.test (from .deps/mini.nvim)
require('mini.test').setup()

-- Load plugin (auto-registers :Winterm command via plugin/winterm.lua)
-- Note: setup() is optional, only needed if you want custom config
require('winterm')

-- Optional: customize config (defaults work fine)
-- require('winterm').setup({
--   win = { height = 0.4, position = 'botright', min_height = 1 },
--   autofocus = true,
--   autoinsert = false,
-- })
