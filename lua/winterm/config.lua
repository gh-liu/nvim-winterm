local M = {}

local defaults = {
	win = {
		height = 0.3, -- 30% of screen height
		position = "botright",
		min_height = 1,
	},
}

local options = vim.tbl_deep_extend("force", {}, defaults)

function M.setup(opts)
	options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

function M.get()
	return options
end

return M
