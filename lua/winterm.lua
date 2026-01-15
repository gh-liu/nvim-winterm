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
					for i, term in ipairs(state.terms) do
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
end

-- Export modules
M.actions = actions
M.api = api
M.state = state
M.winbar = winbar

return M
