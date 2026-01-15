local actions = require("winterm.actions")
local state = require("winterm.state")

local M = {}

local function parse_index_token(args)
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

local function parse_relative_token(args)
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

local function resolve_relative_index(delta, term_count)
	if not state.current_idx then
		return nil
	end
	local base = state.current_idx
	return ((base - 1 + delta) % term_count) + 1
end

-- ============ Window Management ============

function M.toggle()
	actions.toggle()
end

function M.open()
	actions.open()
end

function M.close()
	actions.close()
end

-- ============ Terminal Management ============

function M.run(args, count)
	if not args or args == "" then
		vim.notify("WintermRun: command required", vim.log.levels.ERROR)
		return
	end

	if count and count > 0 then
		vim.notify("WintermRun: index not supported", vim.log.levels.WARN)
	end

	local result = actions.add_term(args, nil)

	if result then
		vim.notify("Terminal created (index: " .. result .. ")", vim.log.levels.INFO)
	else
		vim.notify("Failed to create terminal", vim.log.levels.ERROR)
	end
end

function M.kill(args, bang, count)
	local force = bang and true or false
	local term_count = state.get_term_count()

	if term_count == 0 then
		vim.notify("WintermKill: no terminals", vim.log.levels.WARN)
		return
	end

	if not args or args == "" then
		-- Kill current terminal or count target
		if count and count > 0 then
			if count < 1 or count > term_count then
				vim.notify(string.format("WintermKill: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
				return
			end
			actions.close_term(count, force)
		else
			actions.close_term(nil, force)
		end
	else
		local delta, rest = parse_relative_token(args)
		if delta then
			if rest ~= "" then
				vim.notify("WintermKill: invalid args", vim.log.levels.ERROR)
				return
			end
			local idx = resolve_relative_index(delta, term_count)
			if not idx then
				vim.notify("WintermKill: no current terminal", vim.log.levels.WARN)
				return
			end
			actions.close_term(idx, force)
			return
		end

		local idx, rest = parse_index_token(args)
		if idx and rest ~= "" then
			vim.notify("WintermKill: invalid args", vim.log.levels.ERROR)
			return
		end
		if not idx then
			idx = count
		end
		if not idx or idx < 1 or idx > term_count then
			vim.notify(string.format("WintermKill: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		actions.close_term(idx, force)
	end
end

function M.send(args, count)
	if not args or args == "" then
		vim.notify("WintermSend: content required", vim.log.levels.ERROR)
		return
	end

	local term_count = state.get_term_count()

	local delta, rest = parse_relative_token(args)
	if delta then
		if rest == "" then
			vim.notify("WintermSend: content required", vim.log.levels.ERROR)
			return
		end
		local idx = resolve_relative_index(delta, term_count)
		if not idx then
			vim.notify("WintermSend: no current terminal", vim.log.levels.WARN)
			return
		end
		local success = actions.send_to_term(idx, rest)
		if success then
			vim.notify("Sent to terminal " .. idx, vim.log.levels.INFO)
		else
			vim.notify("Failed to send to terminal", vim.log.levels.WARN)
		end
		return
	end

	-- Parse arguments: [N] {content}
	local idx, content = parse_index_token(args)
	local success
	if idx then
		if idx < 1 or idx > term_count then
			vim.notify(string.format("WintermSend: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		if not content or content == "" then
			vim.notify("WintermSend: content required", vim.log.levels.ERROR)
			return
		end
		success = actions.send_to_term(idx, content)
	else
		local effective_idx = count and count > 0 and count or nil
		if effective_idx and (effective_idx < 1 or effective_idx > term_count) then
			vim.notify(string.format("WintermSend: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		success = actions.send_to_term(effective_idx, args)
	end

	if success then
		local label = idx or (count and count > 0 and count) or "current"
		vim.notify("Sent to terminal " .. label, vim.log.levels.INFO)
	else
		vim.notify("Failed to send to terminal", vim.log.levels.WARN)
	end
end

function M.focus(args, count)
	local term_count = state.get_term_count()
	if term_count == 0 then
		vim.notify("WintermFocus: no terminals", vim.log.levels.WARN)
		return
	end

	if not args or args == "" then
		if count and count > 0 then
			local ok = actions.switch_term(count)
			if not ok then
				vim.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			end
			return
		end
		vim.notify("WintermFocus: index required", vim.log.levels.ERROR)
		return
	end

	local delta, rest = parse_relative_token(args)
	if delta then
		if rest ~= "" then
			vim.notify("WintermFocus: invalid args", vim.log.levels.ERROR)
			return
		end
		local target = resolve_relative_index(delta, term_count)
		if not target then
			vim.notify("WintermFocus: no current terminal", vim.log.levels.WARN)
			return
		end
		local ok = actions.switch_term(target)
		if not ok then
			vim.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
		end
		return
	end

	local idx, rest = parse_index_token(args)
	if idx and rest ~= "" then
		vim.notify("WintermFocus: invalid args", vim.log.levels.ERROR)
		return
	end
	if not idx then
		idx = count
	end
	if not idx or idx < 1 or idx > term_count then
		vim.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
		return
	end

	local ok = actions.switch_term(idx)
	if not ok then
		vim.notify("WintermFocus: failed to switch", vim.log.levels.WARN)
	end
end

return M
