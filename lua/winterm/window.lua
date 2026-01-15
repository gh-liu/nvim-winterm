local config = require("winterm.config")
local state = require("winterm.state")
local winbar = require("winterm.winbar")
local utils = require("winterm.utils")

local M = {}

function M.is_open()
	return state.winnr and state.is_win_valid(state.winnr)
end

function M.open(_opts)
	if M.is_open() then
		-- Window already exists, just focus it
		vim.api.nvim_set_current_win(state.winnr)
		return
	end

	-- Save current window to restore focus later
	local prev_win = vim.api.nvim_get_current_win()

	-- Calculate window height in lines (at least 1)
	local height = math.max(1, math.floor(vim.o.lines * config.get().height))

	-- Open window at the bottom using split
	vim.cmd(string.format("botright %dnew", height))
	local winnr = vim.api.nvim_get_current_win()
	state.winnr = winnr

	-- Set window options
	vim.api.nvim_win_set_option(winnr, "winfixheight", true)
	vim.api.nvim_win_set_option(winnr, "number", false)
	vim.api.nvim_win_set_option(winnr, "relativenumber", false)
	vim.api.nvim_win_set_option(winnr, "signcolumn", "no")

	-- If there's a current term, show it
	local current_term = state.get_current_term()
	if current_term and state.is_buf_valid(current_term.bufnr) then
		vim.api.nvim_win_set_buf(winnr, current_term.bufnr)
	end

	-- Setup winbar
	winbar.setup()
	winbar.refresh()

	-- Restore previous window focus
	utils.restore_window_focus(prev_win, winnr)
end

function M.close()
	if M.is_open() then
		vim.api.nvim_win_close(state.winnr, true)
	end
	state.winnr = nil
	winbar.cleanup()
end

function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

function M.ensure_open(opts)
	if not M.is_open() then
		M.open(opts)
	end
end

return M
