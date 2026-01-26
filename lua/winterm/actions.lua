local config = require("winterm.config")
local state = require("winterm.state")
local terminal = require("winterm.terminal")
local window = require("winterm.window")

local M = {}

function M.setup(opts)
	config.setup(opts)
end

-- Window management
function M.open(opts)
	opts = opts or {}
	window.open(opts)

	local cfg = config.get()

	-- Create a default terminal if none exists
	if not opts.skip_default and state.get_term_count() == 0 then
		local idx = terminal.add_term(vim.o.shell, nil, { cwd = vim.fn.getcwd() })
		-- Apply autofocus and autoinsert settings for default shell
		if idx and cfg.autofocus then
			terminal.switch_term(idx, { auto_insert = cfg.autoinsert })
		end
	elseif state.get_term_count() > 0 and cfg.autofocus then
		-- Apply autofocus and autoinsert when reopening window with existing terminals
		terminal.switch_term(state.current_idx, { auto_insert = cfg.autoinsert })
	end
end

function M.close()
	window.close()
end

function M.toggle()
	if window.is_open() then
		window.close()
	else
		M.open()
	end
end

function M.ensure_open(opts)
	if not window.is_open() then
		M.open(opts)
	end
end

return M
