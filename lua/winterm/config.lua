local M = {}

local options = {
	height = 0.3, -- 30% of screen height
}

function M.setup(opts)
	options = vim.tbl_deep_extend("force", options, opts or {})
end

function M.get()
	return options
end

return M
