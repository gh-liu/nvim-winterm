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

local function strip_cmd_prefix(cmdline_to_cursor)
	if not cmdline_to_cursor then
		return ""
	end
	-- supports :Winterm, :Winterm!, :3Winterm, :3Winterm!, and optional leading spaces
	return cmdline_to_cursor:match("^%s*:?%s*%d*%s*Winterm!?%s*(.*)$") or ""
end

local function tokenize_args(s)
	-- Split on whitespace, but keep quoted segments together. Quotes are kept in tokens.
	-- This is intentionally simple: enough to detect `-dir={path} {cmd}` (and legacy `-dir {path} {cmd}`) shape.
	local tokens = {}
	local cur = {}
	local quote = nil
	for i = 1, #s do
		local c = s:sub(i, i)
		if quote then
			table.insert(cur, c)
			if c == quote then
				quote = nil
			end
		else
			if c == "'" or c == '"' then
				quote = c
				table.insert(cur, c)
			elseif c:match("%s") then
				if #cur > 0 then
					table.insert(tokens, table.concat(cur))
					cur = {}
				end
			else
				table.insert(cur, c)
			end
		end
	end
	if #cur > 0 then
		table.insert(tokens, table.concat(cur))
	end
	return tokens
end

local function dir_completions(arglead)
	local lead = arglead or ""
	local q = lead:sub(1, 1)
	if q == "'" or q == '"' then
		local inner = lead:sub(2)
		local items = vim.fn.getcompletion(inner, "dir")
		for i, v in ipairs(items) do
			items[i] = q .. v
		end
		return items
	end
	return vim.fn.getcompletion(lead, "dir")
end

local function dir_eq_completions(arglead)
	local lead = arglead or ""
	local tail = lead:match("^%-dir=(.*)$") or ""
	local items = dir_completions(tail)
	for i, v in ipairs(items) do
		items[i] = "-dir=" .. v
	end
	return items
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
	complete = function(arglead, cmdline, cursorpos)
		local has_bang = cmdline and cmdline:match("^%s*:?%s*%d*%s*Winterm!") ~= nil

		-- Detect `-dir=... {cmd}` (preferred) and `-dir {path} {cmd}` completion context using content up to cursor.
		local line_to_cursor = cmdline
		if cmdline and cursorpos and cursorpos > 0 then
			line_to_cursor = cmdline:sub(1, cursorpos)
		end
		local args_prefix = strip_cmd_prefix(line_to_cursor or "")
		local tokens = tokenize_args(args_prefix)
		if tokens[1] and tokens[1]:match("^%-dir=") then
			-- `-dir=...` is a single token; complete dirs while cursor stays within it.
			local ends_with_space = args_prefix:match("%s$") ~= nil
			if not ends_with_space then
				return dir_eq_completions(arglead)
			end
			-- Token finished; complete the command instead (fall through).
		elseif tokens[1] == "-dir" then
			local ends_with_space = args_prefix:match("%s$") ~= nil
			-- If we're still on the flag token itself (`-dir<Tab>`), complete the flag (prefer -dir=).
			if #tokens == 1 and not ends_with_space then
				if vim.startswith("-dir", arglead or "") then
					return { "-dir=" }
				end
				return {}
			end
			-- token2 is the directory path, token3+ is the command
			if #tokens == 1 then
				-- Completing the directory argument (nothing typed yet).
				return dir_completions(arglead)
			end
			if #tokens == 2 and not ends_with_space then
				-- Still typing the directory argument.
				return dir_completions(arglead)
			end
			-- Directory is present; complete the command instead (fall through to existing logic).
		elseif (not tokens[1] or tokens[1] == "") and (arglead and arglead:sub(1, 1) == "-") then
			-- `:Winterm -<Tab>` should suggest flags.
			if vim.startswith("-dir", arglead) then
				return { "-dir=" }
			end
			return {}
		elseif tokens[1] and tokens[1]:sub(1, 1) == "-" and #tokens == 1 then
			-- Completing the first token and it looks like a flag
			if vim.startswith("-dir", tokens[1]) then
				return { "-dir=" }
			end
			return {}
		end

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
