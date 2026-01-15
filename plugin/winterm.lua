-- ============ Window Management Commands ============

local function term_items()
	local state = require("winterm.state")
	local items = {}
	for i, term in ipairs(state.terms) do
		table.insert(items, tostring(i))
		table.insert(items, string.format("%d:%s", i, term.cmd))
	end
	return items
end

local subcommands = {
	open = {
		handler = function(_, _)
			require("winterm.api").open()
		end,
	},
	close = {
		handler = function(_, _)
			require("winterm.api").close()
		end,
	},
	run = {
		handler = function(rest, opts)
			require("winterm.api").run(rest, nil)
		end,
		complete = function(line)
			local rest = line:match("^%S+%s+run%s*(.*)$") or ""
			local cmdlead = rest
			local idx_with_space = rest:match("^%d+%s+(.+)$")
			if idx_with_space then
				cmdlead = idx_with_space
			else
				local idx_with_colon = rest:match("^%d+:%S*%s+(.+)$")
				if idx_with_colon then
					cmdlead = idx_with_colon
				end
			end
			return vim.fn.getcompletion(cmdlead, "shellcmd")
		end,
	},
	kill = {
		handler = function(rest, opts)
			require("winterm.api").kill(rest, opts.bang, opts.count)
		end,
		complete = function(_)
			return term_items()
		end,
		accepts_range = true,
	},
	focus = {
		handler = function(rest, opts)
			require("winterm.api").focus(rest, opts.count)
		end,
		complete = function(_)
			return term_items()
		end,
		accepts_range = true,
	},
}

-- Toggle window (most common)
vim.api.nvim_create_user_command("Winterm", function(opts)
	local sub = opts.fargs[1]
	if not sub or sub == "" then
		require("winterm.api").toggle()
		return
	end

	local entry = subcommands[sub]
	if not entry then
		-- Fallback: treat as "run {cmd}" when subcommand is omitted/unknown
		require("winterm.api").run(opts.args, nil)
		return
	end

	local rest = opts.args:match("^%S+%s+(.+)$") or ""
	entry.handler(rest, opts)
end, {
	nargs = "*",
	bang = true,
	count = 0,
	desc = "Winterm {open|close|run|kill|focus}",
	complete = function(_, line)
		local parts = vim.split(line, "%s+")

		local sub = parts[2]
		if not sub or sub == "" then
			return vim.tbl_keys(subcommands)
		end

		local entry = subcommands[sub]
		if entry and entry.complete and line:match("%s$") then
			return entry.complete(line)
		end

		return {}
	end,
})

