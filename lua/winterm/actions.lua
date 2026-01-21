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

	-- Create a default terminal if none exists
	if not opts.skip_default and state.get_term_count() == 0 then
		terminal.add_term(vim.o.shell, nil, { cwd = vim.fn.getcwd() })
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

-- Terminal management
function M.add_term(cmd, idx, opts)
	return terminal.add_term(cmd, idx, opts)
end

function M.switch_term(idx, opts)
	return terminal.switch_term(idx, opts)
end

function M.close_term(idx, force)
	return terminal.close_term(idx, force)
end

-- Send content to terminal
function M.send_to_term(idx, content)
	return terminal.send_to_term(idx, content)
end

return M
