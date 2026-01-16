local state = require("winterm.state")
local winbar = require("winterm.winbar")
local utils = require("winterm.utils")
local window = require("winterm.window")

local M = {}

local function find_term_index_by_bufnr(bufnr)
	for i, term in state.iter_terms() do
		if term.bufnr == bufnr then
			return i
		end
	end
	return nil
end

function M.add_term(cmd, idx, opts)
	window.ensure_open({ skip_default = true })

	-- Save current window to restore later
	local prev_win = vim.api.nvim_get_current_win()
	local prev_buf = vim.api.nvim_win_get_buf(state.winnr)

	-- Switch to winterm window to create terminal there
	vim.api.nvim_set_current_win(state.winnr)

	-- Create a fresh unmodified buffer for termopen
	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(state.winnr, new_buf)
	local bufnr = new_buf

	-- Create terminal buffer
	opts = opts or {}
	if not opts.cwd or opts.cwd == "" then
		opts.cwd = vim.fn.getcwd()
	end
	local on_exit = opts.on_exit
	opts.on_exit = function(job_id, code, event)
		if on_exit then
			on_exit(job_id, code, event)
		end

		if code == 0 then
			return
		end

		vim.schedule(function()
			local term_idx = find_term_index_by_bufnr(bufnr)
			if term_idx then
				M.close_term(term_idx, true)
			end
			utils.echo_error(string.format("WintermRun: command failed (exit %d): %s", code, cmd))
		end)
	end

	local chan_id = vim.fn.termopen(cmd, opts)
	if chan_id == -1 then
		-- termopen failed
		utils.notify("Failed to open terminal: " .. cmd, vim.log.levels.ERROR)
		if state.is_buf_valid(prev_buf) then
			vim.api.nvim_win_set_buf(state.winnr, prev_buf)
		end
		if state.is_buf_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		utils.restore_window_focus(prev_win, state.winnr)
		return nil
	end

	-- Avoid entering terminal insert mode by default
	vim.cmd("stopinsert")

	-- Create term object
	local term = {
		bufnr = bufnr,
		name = cmd:match("^%S+") or cmd, -- Extract first word as name
		cmd = cmd,
		chan_id = chan_id,
		cwd = opts.cwd,
	}

	-- Insert or add term
	local actual_idx
	local term_count = state.get_term_count()
	if idx and idx >= 1 and idx <= term_count + 1 then
		state.insert_term(idx, term)
		actual_idx = idx
	else
		state.add_term(term)
		actual_idx = state.current_idx
	end

	-- Renumber all buffers after insertion
	state.renumber_buffers()

	-- Switch to the new term
	utils.with_winfixbuf_disabled(state.winnr, function()
		vim.api.nvim_win_set_buf(state.winnr, bufnr)
	end)
	winbar.refresh()

	-- Restore previous window focus
	utils.restore_window_focus(prev_win, state.winnr)

	return actual_idx
end

function M.switch_term(idx)
	if not idx or idx < 1 or idx > state.get_term_count() then
		return false
	end

	local term = state.get_term(idx)
	if not term or not state.is_buf_valid(term.bufnr) then
		return false
	end

	-- Ensure window is open
	window.ensure_open()

	-- Switch buffer in window
	utils.with_winfixbuf_disabled(state.winnr, function()
		vim.api.nvim_win_set_buf(state.winnr, term.bufnr)
	end)

	-- Update current index
	state.set_current(idx)

	-- Refresh winbar
	winbar.refresh()

	return true
end

function M.close_term(idx, force)
	local term_count = state.get_term_count()
	if term_count == 0 then
		return false
	end

	-- Determine which term to close
	local close_idx = idx
	if not close_idx then
		close_idx = state.current_idx
	end

	if not close_idx or close_idx < 1 or close_idx > term_count then
		return false
	end

	local term = state.get_term(close_idx)
	if not term then
		return false
	end

	-- Delete buffer
	if state.is_buf_valid(term.bufnr) then
		local ok, err = pcall(vim.api.nvim_buf_delete, term.bufnr, { force = force or false })
		if not ok then
			if force then
				utils.notify("Failed to close terminal: " .. (err or "unknown error"), vim.log.levels.ERROR)
			else
				utils.notify("Terminal is still running. Use :Winterm! kill to force.", vim.log.levels.WARN)
			end
			return false
		end
	end

	-- Remove from state
	local was_current = close_idx == state.current_idx
	state.remove_term(close_idx)

	-- If no terms left, close window
	if state.get_term_count() == 0 then
		window.close()
		return true
	end

	-- Renumber remaining buffers
	state.renumber_buffers()

	-- Switch to another term if needed
	if was_current then
		-- Switch to previous or next term
		local new_idx = math.min(close_idx, state.get_term_count())
		M.switch_term(new_idx)
	else
		winbar.refresh()
	end

	return true
end

function M.send_to_term(idx, content)
	local term_count = state.get_term_count()
	if term_count == 0 then
		return false
	end

	-- Ensure window is open so user can see terminal
	window.ensure_open()

	local target_idx = idx or state.current_idx
	if not target_idx or target_idx < 1 or target_idx > term_count then
		return false
	end

	local term = state.get_term(target_idx)
	if not term or not term.chan_id or term.chan_id <= 0 then
		return false
	end

	if not content or content == "" then
		return false
	end

	-- Ensure content ends with newline if it doesn't already
	local content_to_send = content
	if not content:match("\n$") then
		content_to_send = content .. "\n"
	end

	-- Send content to terminal channel (with error handling)
	local ok, err = pcall(vim.api.nvim_chan_send, term.chan_id, content_to_send)
	if not ok then
		utils.notify("Failed to send to terminal: " .. (err or "unknown error"), vim.log.levels.WARN)
		return false
	end

	return true
end

return M
