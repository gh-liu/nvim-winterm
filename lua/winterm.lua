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

	-- Handle BufWipeout: unified cleanup when buffer is deleted
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = cleanup_group,
		callback = function(event)
			-- Check if this is a winterm buffer
			local term_idx = nil
			for i, term in state.iter_terms() do
				if term.bufnr == event.buf then
					term_idx = i
					break
				end
			end

			-- If not a winterm buffer, do nothing
			if not term_idx then
				return
			end

			-- Remove from state
			state.remove_term(term_idx)

			-- If no terms left, close window
			if state.get_term_count() == 0 then
				require("winterm.window").close()
				return
			end

			-- Renumber remaining buffers
			state.renumber_buffers()

			-- Switch to previous term
			local new_idx = math.min(term_idx, state.get_term_count())
			require("winterm.terminal").switch_term(new_idx, { auto_insert = false })
		end,
	})

	-- on_key listener: handle input in insert mode for exited terminals
	vim.on_key(function(key)
		-- Only process if in insert mode
		local mode = vim.fn.mode()
		if mode ~= "i" then
			return
		end

		-- Check if current buffer is a closed winterm
		local bufnr = vim.api.nvim_get_current_buf()
		local term = state.find_term_by_bufnr(bufnr)
		if not term or not term.is_closed then
			return
		end

		-- Don't trigger on mode-switching keys or special keys
		-- Mode switch: Esc, Ctrl-\Ctrl-n
		if key == "\27" or key == "\28\14" then
			return
		end

		-- Delete the buffer, which will trigger BufWipeout
		vim.api.nvim_buf_delete(bufnr, { force = true })
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
