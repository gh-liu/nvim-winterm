-- ============ Window Management Commands ============

local function term_items()
	local state = require("winterm.state")
	local items = {}
	for i, term in ipairs(state.terms) do
		-- table.insert(items, tostring(i))
		table.insert(items, string.format("%d:%s", i, term.cmd))
	end
	return items
end

local function looks_like_index_token(token)
	if not token or token == "" then
		return false
	end
	if token:match("^[+-]%d+$") then
		return true
	end
	if token:match("^:%d+$") then
		return true
	end
	if token:match("^%d+$") then
		return true
	end
	return false
end

local function parse_label_index(args)
	if not args or args == "" then
		return nil
	end
	local idx_str = args:match("^:?(%d+):")
	if not idx_str then
		return nil
	end
	return tonumber(idx_str)
end

local function normalize_index_arg(args)
	if not args or args == "" then
		return args
	end
	local idx_str = args:match("^:(%d+)$")
	if idx_str then
		return idx_str
	end
	return args
end

-- Toggle window (most common)
vim.api.nvim_create_user_command("Winterm", function(opts)
	local sub = opts.fargs[1]
	if not sub or sub == "" or vim.startswith(sub, ":") then
		if opts.bang then
			require("winterm.api").kill("", true, opts.count)
			return
		end
		if opts.count and opts.count > 0 then
			require("winterm.api").focus("", opts.count)
			return
		end
		require("winterm.api").toggle()
		return
	end

	local label_idx = parse_label_index(opts.args)
	if label_idx then
		if opts.bang then
			require("winterm.api").kill(tostring(label_idx), true, opts.count)
		else
			require("winterm.api").focus(tostring(label_idx), opts.count)
		end
		return
	end

	if looks_like_index_token(sub) then
		local normalized_args = normalize_index_arg(opts.args)
		if opts.bang then
			require("winterm.api").kill(normalized_args, true, opts.count)
		else
			require("winterm.api").focus(normalized_args, opts.count)
		end
		return
	end
	require("winterm.api").run(opts.args, nil)
end, {
	nargs = "*",
	bang = true,
	count = 0,
	force = true,
	desc = "Winterm [cmd|index]",
	complete = function(arglead, cmdline, _)
		local has_bang = cmdline and cmdline:match("^%s*:??%s*Winterm!") ~= nil
		if not arglead or arglead == "" then
			if has_bang then
				return term_items()
			end
			local items = term_items()
			local cmds = vim.fn.getcompletion("", "shellcmd")
			for _, cmd in ipairs(cmds) do
				table.insert(items, cmd)
			end
			return items
		end
		if looks_like_index_token(arglead) then
			return term_items()
		end
		return vim.fn.getcompletion(arglead, "shellcmd")
	end,
})
