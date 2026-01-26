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

	-- Calculate window height in lines
	local win_opts = config.get().win or {}
	local height_ratio = win_opts.height or 0.3
	local min_height = win_opts.min_height or 1
	local position = win_opts.position or "botright"
	local height = math.max(min_height, math.floor(vim.o.lines * height_ratio))

	-- Open window at the bottom using split
	vim.cmd(string.format("%s %dnew", position, height))
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
		local prev_win = nil
		local current_win = vim.api.nvim_get_current_win()
		if current_win == state.winnr then
			local prev_winnr = vim.fn.winnr("#")
			if prev_winnr and prev_winnr > 0 then
				local winid = vim.fn.win_getid(prev_winnr)
				-- Validate window before storing it
				if winid and state.is_win_valid(winid) then
					prev_win = winid
				end
			end
		end
		vim.api.nvim_win_close(state.winnr, true)
		if prev_win and state.is_win_valid(prev_win) then
			vim.api.nvim_set_current_win(prev_win)
		end
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
