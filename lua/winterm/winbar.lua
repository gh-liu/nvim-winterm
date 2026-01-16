local state = require("winterm.state")

local M = {}

local winbar_group = vim.api.nvim_create_augroup("WintermWinbar", { clear = true })
local winbar_autocmd_set = false
local winbar_hl_set = false
local last_winbar = nil -- Cache for avoiding redundant updates

function M.render()
	if state.get_term_count() == 0 then
		return ""
	end

	local parts = {}
	for i, term in state.iter_terms() do
		local cmd = term.cmd:gsub("%%", "%%%%")
		local label = string.format("%d:%s", i, cmd)
		if i == state.current_idx then
			-- Highlight current term
			table.insert(parts, string.format("%%#WintermWinbarSel# %s %%#WintermWinbar#", label))
		else
			table.insert(parts, string.format("%%#WintermWinbar# %s %%#WintermWinbar#", label))
		end
	end

	return table.concat(parts, "%#WintermWinbar#|")
end

function M.refresh()
	if not state.winnr or not state.is_win_valid(state.winnr) then
		return
	end

	local winbar_str = M.render()

	-- Only update if content changed
	if winbar_str == last_winbar then
		return
	end

	last_winbar = winbar_str
	vim.api.nvim_win_set_option(state.winnr, "winbar", winbar_str)
end

function M.setup()
	if not state.winnr or not state.is_win_valid(state.winnr) then
		return
	end

	if not winbar_hl_set then
		winbar_hl_set = true
		vim.api.nvim_set_hl(0, "WintermWinbar", { link = "TabLine" })
		vim.api.nvim_set_hl(0, "WintermWinbarSel", { link = "TabLineSel" })
	end

	-- Set initial winbar
	M.refresh()

	-- Create autocmd to refresh winbar on window events (only once)
	if not winbar_autocmd_set then
		winbar_autocmd_set = true
		-- Only listen to WinEnter to filter unnecessary BufEnter events
		vim.api.nvim_create_autocmd("WinEnter", {
			group = winbar_group,
			callback = function()
				-- Only refresh if we're in the winterm window
				if state.winnr and state.is_win_valid(state.winnr) then
					local current_win = vim.api.nvim_get_current_win()
					if current_win == state.winnr then
						M.refresh()
					end
				end
			end,
		})
	end
end

function M.cleanup()
	winbar_autocmd_set = false
	last_winbar = nil
	vim.api.nvim_clear_autocmds({ group = winbar_group })
end

return M
