local state = require("winterm.state")

local M = {}

function M.with_winfixbuf_disabled(winnr, fn)
	if not state.is_win_valid(winnr) then
		return fn()
	end

	local ok_get, prev = pcall(vim.api.nvim_win_get_option, winnr, "winfixbuf")
	if ok_get and prev then
		pcall(vim.api.nvim_win_set_option, winnr, "winfixbuf", false)
	end

	local ok, result = pcall(fn)

	if ok_get and prev then
		pcall(vim.api.nvim_win_set_option, winnr, "winfixbuf", true)
	end

	if not ok then
		error(result)
	end

	return result
end

function M.restore_window_focus(prev_win, current_winnr)
	if state.is_win_valid(prev_win) and prev_win ~= current_winnr then
		vim.api.nvim_set_current_win(prev_win)
	end
end

return M
