---@class winterm.Term
---@field bufnr integer
---@field winnr? integer
---@field name string
---@field cmd string
---@field job_id integer

---@class winterm.State
local M = {
	-- Internal storage; prefer accessors (list_terms/get_term_labels/iter_terms).
	---@type winterm.Term[]
	terms = {},
	---@type integer?
	current_idx = nil,
	---@type integer?
	winnr = nil,
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
	M.current_idx = #M.terms
	return #M.terms
end

function M.insert_term(idx, term)
	table.insert(M.terms, idx, term)
	M.current_idx = idx
	return idx
end

function M.remove_term(idx)
	local removed = table.remove(M.terms, idx)
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
end

-- Renumber all buffers (rebuild buffer names)
function M.renumber_buffers()
	local utils = require("winterm.utils")
	for i, term in ipairs(M.terms) do
		if M.is_buf_valid(term.bufnr) then
			utils.safe_buf_set_name(term.bufnr, string.format("%d:%s", i, term.cmd))
		end
	end
end

return M
