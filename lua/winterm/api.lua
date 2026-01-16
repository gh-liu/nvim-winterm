local actions = require("winterm.actions")
local cli = require("winterm.cli")
local state = require("winterm.state")
local utils = require("winterm.utils")

local M = {}

local function parse_index_token(args)
	return cli.parse_index_token(args)
end

local function parse_relative_token(args)
	return cli.parse_relative_token(args)
end

local function resolve_relative_index(delta, term_count)
	return cli.resolve_relative_index(delta, term_count)
end

local function parse_dir_option(args)
	return cli.parse_dir_option(args)
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

---@param args string
---@param count integer?
function M.run(args, count)
	if not args or args == "" then
		utils.notify("WintermRun: command required", vim.log.levels.ERROR)
		return
	end

	if count and count > 0 then
		utils.notify("WintermRun: index not supported", vim.log.levels.WARN)
	end

	local dir, cmd, err = parse_dir_option(args)
	if err then
		utils.notify(err, vim.log.levels.ERROR)
		return
	end
	if not cmd or cmd == "" then
		utils.notify("WintermRun: command required", vim.log.levels.ERROR)
		return
	end

	local cwd = dir or vim.fn.getcwd()
	local result = actions.add_term(cmd, nil, { cwd = cwd })

	if result then
		utils.notify("Terminal created (index: " .. result .. ")", vim.log.levels.INFO)
	else
		utils.notify("Failed to create terminal", vim.log.levels.ERROR)
	end
end

---@param args string?
---@param bang boolean
---@param count integer?
function M.kill(args, bang, count)
	local force = bang and true or false
	local term_count = state.get_term_count()

	if term_count == 0 then
		utils.notify("WintermKill: no terminals", vim.log.levels.WARN)
		return
	end

	if not args or args == "" then
		-- Kill current terminal or count target
		if count and count > 0 then
			if count < 1 or count > term_count then
				utils.notify(string.format("WintermKill: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
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
				utils.notify("WintermKill: no current terminal", vim.log.levels.WARN)
				return
			end
			actions.close_term(idx, force)
			return
		end

		local idx, rest = parse_index_token(args)
		if idx and rest ~= "" then
			utils.notify("WintermKill: invalid args", vim.log.levels.ERROR)
			return
		end
		if not idx then
			idx = count
		end
		if not idx or idx < 1 or idx > term_count then
			utils.notify(string.format("WintermKill: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		actions.close_term(idx, force)
	end
end

---@param args string
---@param count integer?
function M.send(args, count)
	if not args or args == "" then
		utils.notify("WintermSend: content required", vim.log.levels.ERROR)
		return
	end

	local term_count = state.get_term_count()

	local delta, rest = parse_relative_token(args)
	if delta then
		if rest == "" then
			utils.notify("WintermSend: content required", vim.log.levels.ERROR)
			return
		end
		local idx = resolve_relative_index(delta, term_count)
		if not idx then
			utils.notify("WintermSend: no current terminal", vim.log.levels.WARN)
			return
		end
		local success = actions.send_to_term(idx, rest)
		if success then
			utils.notify("Sent to terminal " .. idx, vim.log.levels.INFO)
		else
			utils.notify("Failed to send to terminal", vim.log.levels.WARN)
		end
		return
	end

	-- Parse arguments: [N] {content}
	local idx, content = parse_index_token(args)
	local success
	if idx then
		if idx < 1 or idx > term_count then
			utils.notify(string.format("WintermSend: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		if not content or content == "" then
			utils.notify("WintermSend: content required", vim.log.levels.ERROR)
			return
		end
		success = actions.send_to_term(idx, content)
	else
		local effective_idx = count and count > 0 and count or nil
		if effective_idx and (effective_idx < 1 or effective_idx > term_count) then
			utils.notify(string.format("WintermSend: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			return
		end
		success = actions.send_to_term(effective_idx, args)
	end

	if success then
		local label = idx or (count and count > 0 and count) or "current"
		utils.notify("Sent to terminal " .. label, vim.log.levels.INFO)
	else
		utils.notify("Failed to send to terminal", vim.log.levels.WARN)
	end
end

---@param args string?
---@param count integer?
function M.focus(args, count)
	local term_count = state.get_term_count()
	if term_count == 0 then
		utils.notify("WintermFocus: no terminals", vim.log.levels.WARN)
		return
	end

	if not args or args == "" then
		if count and count > 0 then
			local ok = actions.switch_term(count)
			if not ok then
				utils.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
			end
			return
		end
		utils.notify("WintermFocus: index required", vim.log.levels.ERROR)
		return
	end

	local delta, rest = parse_relative_token(args)
	if delta then
		if rest ~= "" then
			utils.notify("WintermFocus: invalid args", vim.log.levels.ERROR)
			return
		end
		local target = resolve_relative_index(delta, term_count)
		if not target then
			utils.notify("WintermFocus: no current terminal", vim.log.levels.WARN)
			return
		end
		local ok = actions.switch_term(target)
		if not ok then
			utils.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
		end
		return
	end

	local idx, rest = parse_index_token(args)
	if idx and rest ~= "" then
		utils.notify("WintermFocus: invalid args", vim.log.levels.ERROR)
		return
	end
	if not idx then
		idx = count
	end
	if not idx or idx < 1 or idx > term_count then
		utils.notify(string.format("WintermFocus: invalid index (1-%d)", term_count), vim.log.levels.ERROR)
		return
	end

	local ok = actions.switch_term(idx)
	if not ok then
		utils.notify("WintermFocus: failed to switch", vim.log.levels.WARN)
	end
end

return M
