---@class winterm.Term
---@field bufnr integer
---@field winnr? integer
---@field name string
---@field cmd string
---@field job_id integer
---@field is_closed boolean

---@class winterm.State
local M = {
	-- Internal storage; prefer accessors (list_terms/get_term_labels/iter_terms).
	---@type winterm.Term[]
	terms = {},
	---@type integer?
	current_idx = nil,
	---@type integer?
	winnr = nil,
	---@type integer?
	last_non_winterm_win = nil,
	---@type table<integer, boolean>
	-- Job IDs marked for cleanup (persists across reloads)
	killed_jobs = {},
	---@type table<integer, integer>
	-- Cache: bufnr → idx mapping for O(1) lookup
	_bufnr_index = {},
}

function M.is_win_valid(winnr)
	return winnr and winnr > 0 and vim.api.nvim_win_is_valid(winnr)
end

function M.is_buf_valid(bufnr)
	return bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr)
end

function M.get_current_term()
	if M.current_idx and M.terms[M.current_idx] then
		return M.terms[M.current_idx]
	end
	return nil
end

function M.get_term(idx)
	return M.terms[idx]
end

function M.get_term_count()
	return #M.terms
end

function M.list_terms()
	local copy = {}
	for i, term in ipairs(M.terms) do
		copy[i] = term
	end
	return copy
end

function M.iter_terms()
	return ipairs(M.terms)
end

function M.find_term_by_bufnr(bufnr)
	for _, term in ipairs(M.terms) do
		if term.bufnr == bufnr then
			return term
		end
	end
	return nil
end

function M.find_term_index_by_bufnr(bufnr)
	-- Use O(1) cache lookup instead of O(n) linear scan
	return M._bufnr_index[bufnr]
end

function M.get_term_labels()
	local labels = {}
	for i, term in ipairs(M.terms) do
		labels[i] = string.format("%d:%s", i, term.cmd)
	end
	return labels
end

function M.set_current(idx)
	M.current_idx = idx
end

function M.add_term(term)
	table.insert(M.terms, term)
	local idx = #M.terms
	-- Update cache: bufnr → idx mapping for O(1) lookup
	if term.bufnr then
		M._bufnr_index[term.bufnr] = idx
	end
	-- Don't auto-set current_idx here - let caller decide
	-- This separates add operation from focus management (SRP)
	return idx
end

function M.insert_term(idx, term)
	table.insert(M.terms, idx, term)
	-- Rebuild cache after insertion (indices may have changed)
	M._bufnr_index = {}
	for i, t in ipairs(M.terms) do
		if t.bufnr then
			M._bufnr_index[t.bufnr] = i
		end
	end
	-- Don't auto-set current_idx here - let caller decide
	-- This separates insert operation from focus management (SRP)
	return idx
end

function M.remove_term(idx)
	local removed = table.remove(M.terms, idx)
	-- Remove from cache
	if removed and removed.bufnr then
		M._bufnr_index[removed.bufnr] = nil
	end
	-- Rebuild cache after removal (indices may have changed)
	M._bufnr_index = {}
	for i, t in ipairs(M.terms) do
		if t.bufnr then
			M._bufnr_index[t.bufnr] = i
		end
	end
	local count = #M.terms
	if count == 0 then
		M.current_idx = nil
	elseif M.current_idx and M.current_idx > count then
		M.current_idx = count
	elseif M.current_idx and M.current_idx >= idx then
		M.current_idx = math.max(1, M.current_idx - 1)
	end
	return removed
end

function M.clear()
	local utils = require("winterm.utils")
	for _, term in ipairs(M.terms) do
		if M.is_buf_valid(term.bufnr) then
			utils.safe_buf_delete(term.bufnr, { force = true })
		end
	end
	M.terms = {}
	M.current_idx = nil
	M.killed_jobs = {}
	M._bufnr_index = {}
end

-- Clean up stale job IDs from killed_jobs to prevent memory leaks
-- Removes job IDs that are no longer referenced by any terminal in state
function M.cleanup_killed_jobs()
	-- Build set of active job IDs from current terminals
	local active_jobs = {}
	for _, term in ipairs(M.terms) do
		if term.job_id and term.job_id > 0 then
			active_jobs[term.job_id] = true
		end
	end
	-- Remove killed_jobs entries that are not in active jobs
	-- (i.e., the terminal was already removed from state)
	for job_id in pairs(M.killed_jobs) do
		if not active_jobs[job_id] then
			M.killed_jobs[job_id] = nil
		end
	end
end

-- Renumber all buffers (rebuild buffer names)
function M.renumber_buffers()
	local utils = require("winterm.utils")
	for i, term in ipairs(M.terms) do
		if M.is_buf_valid(term.bufnr) then
			-- Truncate command to 100 characters to prevent buffer name truncation
			local cmd_display = term.cmd
			if #cmd_display > 100 then
				cmd_display = cmd_display:sub(1, 100)
			end
			utils.safe_buf_set_name(term.bufnr, string.format("%d:%s", i, cmd_display))
		end
	end
end

return M
