local M = {}

function M.notify(msg, level, opts)
	local notify_opts = opts or {}
	if notify_opts.title == nil then
		notify_opts.title = "Winterm"
	end
	vim.notify(msg, level or vim.log.levels.INFO, notify_opts)
end

function M.echo(msg, hl)
	vim.api.nvim_echo({ { msg, hl or "None" } }, true, {})
end

function M.echo_error(msg)
	M.echo(msg, "ErrorMsg")
end

function M.pcall_notify(fn, err_msg, level)
	local ok, result = pcall(fn)
	if ok then
		return true, result
	end

	local msg = err_msg
	if type(err_msg) == "function" then
		msg = err_msg(result)
	end
	if msg and msg ~= "" then
		M.notify(msg, level or vim.log.levels.ERROR)
	end
	return false, result
end

function M.safe_buf_delete(bufnr, opts, err_msg, level)
	return M.pcall_notify(function()
		vim.api.nvim_buf_delete(bufnr, opts or {})
	end, err_msg, level)
end

function M.safe_buf_set_name(bufnr, name)
	local ok = pcall(vim.api.nvim_buf_set_name, bufnr, name)
	return ok
end

function M.with_winfixbuf_disabled(winnr, fn)
	local state = require("winterm.state")
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
	local state = require("winterm.state")
	if state.is_win_valid(prev_win) and prev_win ~= current_winnr then
		vim.api.nvim_set_current_win(prev_win)
	end
end

return M
