local M = {}

local defaults = {
	height = 0.3, -- Backward-compatible shortcut; mirrors win.height
	win = {
		height = 0.3, -- 30% of screen height
		position = "botright",
		min_height = 1,
	},
}

local options = vim.tbl_deep_extend("force", {}, defaults)

function M.setup(opts)
	options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

	if opts and opts.height ~= nil and (not opts.win or opts.win.height == nil) then
		options.win.height = opts.height
	end

	-- Keep top-level height in sync for compatibility.
	options.height = options.win.height
end

function M.get()
	return options
end

return M
