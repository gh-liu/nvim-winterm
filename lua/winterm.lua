local actions = require("winterm.actions")
local api = require("winterm.api")
local state = require("winterm.state")
local winbar = require("winterm.winbar")

local M = {}

function M.setup(opts)
	opts = opts or {}

	-- Setup actions with config
	actions.setup(opts)

	-- Setup autocmds for cleanup
	local cleanup_group = vim.api.nvim_create_augroup("WintermCleanup", { clear = true })

	-- Cleanup on VimLeavePre
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = cleanup_group,
		callback = function()
			state.clear()
			winbar.cleanup()
		end,
	})

	-- Handle window close events
	vim.api.nvim_create_autocmd("WinClosed", {
		group = cleanup_group,
		callback = function(event)
			if state.winnr and event.match == tostring(state.winnr) then
				-- Window was closed, clear state
				state.winnr = nil
				winbar.cleanup()
				if state.is_win_valid(state.last_non_winterm_win) then
					vim.api.nvim_set_current_win(state.last_non_winterm_win)
				end
			end
		end,
	})

	-- Track last non-winterm window for WinClosed restore
	vim.api.nvim_create_autocmd("WinEnter", {
		group = cleanup_group,
		callback = function()
			if state.winnr and state.is_win_valid(state.winnr) then
				local current_win = vim.api.nvim_get_current_win()
				if current_win ~= state.winnr then
					state.last_non_winterm_win = current_win
				end
			end
		end,
	})

	-- Update current index on BufEnter in winterm window
	vim.api.nvim_create_autocmd("BufEnter", {
		group = cleanup_group,
		callback = function()
			if state.winnr and state.is_win_valid(state.winnr) then
				local current_win = vim.api.nvim_get_current_win()
				if current_win == state.winnr then
					local current_buf = vim.api.nvim_get_current_buf()
					-- Find which term this buffer belongs to
					for i, term in state.iter_terms() do
						if term.bufnr == current_buf then
							state.set_current(i)
							winbar.refresh()
							break
						end
					end
				end
			end
		end,
	})

	-- on_key listener: auto-switch and cleanup when pressing key in a closed terminal
	vim.on_key(function(key)
		-- Check if current buffer is a winterm buffer
		local bufnr = vim.api.nvim_get_current_buf()
		local term = state.find_term_by_bufnr(bufnr)
		if not term then
			return
		end

		-- Only process if in terminal mode
		local mode = vim.fn.mode()
		if mode ~= "t" then
			return
		end

		-- Check if terminal is closed
		if not term.is_closed then
			return
		end

		-- Don't trigger on mode-switching keys
		-- In terminal mode, Ctrl-\ (0x1C) followed by Ctrl-N (0x0E) exits terminal mode
		-- Also skip Esc (0x1B) which is sent in some terminal configurations
		local byte_val = string.byte(key)
		if byte_val == 28 or byte_val == 14 or byte_val == 27 then -- Ctrl-\, Ctrl-N, Esc
			return
		end

		-- Find current term index (the closed one)
		local closed_idx = state.find_term_index_by_bufnr(bufnr)
		if not closed_idx then
			return
		end

		local term_count = state.get_term_count()
		if term_count == 1 then
			-- Only one terminal, just close it (will close window too)
			require("winterm.terminal").close_term(closed_idx, true)
			return
		end

		-- Get the target index we should switch to
		local target_idx
		if closed_idx < term_count then
			target_idx = closed_idx + 1
		else
			target_idx = closed_idx - 1
		end

		-- Only switch if not already at target (avoids double-switch from user keybindings)
		if state.current_idx ~= target_idx then
			require("winterm.terminal").switch_term(target_idx, { auto_insert = true })
		end
		-- Always cleanup the closed terminal
		require("winterm.terminal").close_term(closed_idx, true)
	end)
end

-- Export modules
M.run = api.run_term
M.list = api.list_terms
M.actions = actions
M.api = api
M.state = state
M.winbar = winbar

return M
