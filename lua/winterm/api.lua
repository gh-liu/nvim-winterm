local actions = require("winterm.actions")
local cli = require("winterm.cli")
local config = require("winterm.config")
local state = require("winterm.state")
local terminal = require("winterm.terminal")
local utils = require("winterm.utils")

local M = {}

-- Stable term handle (identified by bufnr). idx is resolved dynamically.
local Term = {}
Term.__index = Term

local function resolve_idx_by_bufnr(bufnr)
	for i, t in state.iter_terms() do
		if t.bufnr == bufnr then
			return i, t
		end
	end
	return nil, nil
end

function Term:idx()
	local idx = resolve_idx_by_bufnr(self.bufnr)
	return idx
end

function Term:focus()
	local idx = self:idx()
	if not idx then
		return false
	end
	return terminal.switch_term(idx)
end

local function new_term_obj(t)
	return setmetatable({
		bufnr = t.bufnr,
		cmd = t.cmd,
		cwd = t.cwd,
	}, Term)
end

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
	local result = terminal.add_term(cmd, nil, { cwd = cwd })

	if result then
		utils.notify("Terminal created (index: " .. result .. ")", vim.log.levels.INFO)

		-- Auto focus terminal if configured
		local cfg = config.get()
		if cfg.autofocus then
			local ok = terminal.switch_term(result, { auto_insert = cfg.autoinsert })
			if not ok then
				utils.notify("Failed to focus terminal", vim.log.levels.WARN)
			end
		end
	else
		utils.notify("Failed to create terminal", vim.log.levels.ERROR)
	end
end

-- Run a command and return a stable term object (identified by bufnr).
---@param cmd string
---@param opts table? { cwd?: string, focus?: boolean }
---@return table|nil
function M.run_term(cmd, opts)
	if not cmd or cmd == "" then
		utils.notify("Winterm.run: command required", vim.log.levels.ERROR)
		return nil
	end

	opts = opts or {}
	local cwd = opts.cwd or vim.fn.getcwd()

	local idx = terminal.add_term(cmd, nil, { cwd = cwd })
	if not idx then
		return nil
	end

	local t = state.get_term(idx)
	if not t then
		return nil
	end

	local term_obj = new_term_obj(t)
	if opts.focus == true then
		term_obj:focus()
	end
	return term_obj
end

-- List all terminals as term objects (stable handles by bufnr).
---@return table[]
function M.list_terms()
	local items = {}
	for _, t in state.iter_terms() do
		items[#items + 1] = new_term_obj(t)
	end
	return items
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
			terminal.close_term(count, force)
		else
			terminal.close_term(nil, force)
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
			terminal.close_term(idx, force)
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
		terminal.close_term(idx, force)
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

	local cfg = config.get()

	if not args or args == "" then
		if count and count > 0 then
			local ok = terminal.switch_term(count, { auto_insert = cfg.autoinsert })
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
		local ok = terminal.switch_term(target, { auto_insert = cfg.autoinsert })
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

	local ok = terminal.switch_term(idx, { auto_insert = cfg.autoinsert })
	if not ok then
		utils.notify("WintermFocus: failed to switch", vim.log.levels.WARN)
	end
end

return M
