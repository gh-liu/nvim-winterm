local state = require("winterm.state")

local M = {}

local function term_items()
	return state.get_term_labels()
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
	-- This is intentionally simple: enough to detect `-dir={path} {cmd}` shape.
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

function M.parse_index_token(args)
	if not args or args == "" then
		return nil, ""
	end

	local token, rest = args:match("^(%S+)%s*(.*)$")
	if not token then
		return nil, ""
	end

	local idx_str = token:match("^(%d+):") or token
	local idx = tonumber(idx_str)
	return idx, rest or ""
end

function M.parse_relative_token(args)
	if not args or args == "" then
		return nil, ""
	end

	local sign, num, rest = args:match("^([+-])(%d+)%s*(.*)$")
	if not sign then
		return nil, args
	end

	local delta = tonumber(sign .. num)
	return delta, rest or ""
end

function M.resolve_relative_index(delta, term_count)
	if not state.current_idx then
		return nil
	end
	local base = state.current_idx
	return ((base - 1 + delta) % term_count) + 1
end

function M.parse_dir_option(args)
	if not args or args == "" then
		return nil, ""
	end

	local trimmed = vim.trim(args)
	-- Only treat `-dir` as an option when it is exactly `-dir`, `-dir=...`, or `-dir ...`.
	if not trimmed:match("^%-dir(%s|=|$)") then
		return nil, args
	end

	-- Support both `-dir {path}` and `-dir={path}`.
	local dir, rest

	-- New form: -dir=...
	if trimmed:match("^%-dir=") then
		dir, rest = trimmed:match('^%-dir=%s*"([^"]+)"%s*(.*)$')
		if not dir then
			dir, rest = trimmed:match("^%-dir=%s+'([^']+)'%s*(.*)$")
		end
		if not dir then
			dir, rest = trimmed:match("^%-dir=([^%s]+)%s*(.*)$")
		end
		if not dir then
			return nil, nil, "WintermRun: -dir= requires a path"
		end
		return dir, rest or ""
	end

	-- Old form: -dir ...
	dir, rest = trimmed:match('^%-dir%s+"([^"]+)"%s*(.*)$')
	if not dir then
		dir, rest = trimmed:match("^%-dir%s+'([^']+)'%s*(.*)$")
	end
	if not dir then
		dir, rest = trimmed:match("^%-dir%s+(%S+)%s*(.*)$")
	end
	if not dir then
		return nil, nil, "WintermRun: -dir requires a path"
	end

	return dir, rest or ""
end

function M.complete_winterm(arglead, cmdline, cursorpos)
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
end

function M.parse_label_index(args)
	return parse_label_index(args)
end

function M.looks_like_index_token(token)
	return looks_like_index_token(token)
end

function M.normalize_index_arg(args)
	return normalize_index_arg(args)
end

return M
