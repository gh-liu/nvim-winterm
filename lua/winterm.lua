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

	-- Handle finished command buffers being wiped out by user interaction
	-- When a finished command's buffer is wiped out (user presses keys), we need to:
	-- 1. Remove it from state
	-- 2. Check window state and handle appropriately:
	--    - If window closed: reopen and show another terminal
	--    - If window shows invalid buffer: switch to valid terminal
	--    - If window shows valid buffer: just refresh UI
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = cleanup_group,
		callback = function(event)
			-- Find if this buffer belongs to any term
			local removed_idx = nil
			for i, term in state.iter_terms() do
				if term.bufnr == event.buf then
					removed_idx = i
					break
				end
			end

			if not removed_idx then
				return
			end

			local window = require("winterm.window")

			-- Remove the finished term from state
			state.remove_term(removed_idx)
			state.renumber_buffers()

			-- If no terms left, close window and exit
			if state.get_term_count() == 0 then
				if window.is_open() then
					window.close()
				end
				return
			end

			-- Calculate which term to show
			local target_idx = math.min(removed_idx, state.get_term_count())
			if target_idx < 1 then
				target_idx = 1
			end

			-- Handle different window states
			if window.is_open() then
				local current_buf = vim.api.nvim_win_get_buf(state.winnr)
				if state.is_buf_valid(current_buf) then
					-- Window shows a valid buffer, just refresh UI
					winbar.refresh()
				else
					-- Window shows invalid buffer, switch to valid terminal immediately
					vim.schedule(function()
						if window.is_open() and state.get_term_count() > 0 then
							require("winterm.terminal").switch_term(target_idx, { auto_insert = false })
						end
					end)
				end
			else
				-- Window was closed, reopen it and show a terminal
				vim.schedule(function()
					if state.get_term_count() > 0 then
						window.ensure_open()
						require("winterm.terminal").switch_term(target_idx, { auto_insert = false })
					end
				end)
			end
		end,
	})
end

-- Export modules
M.run = api.run_term
M.list = api.list_terms
M.actions = actions
M.api = api
M.state = state
M.winbar = winbar

return M
