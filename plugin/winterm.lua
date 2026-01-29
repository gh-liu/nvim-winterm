-- ============ Window Management Commands ============

-- Toggle window (most common)
vim.api.nvim_create_user_command("Winterm", function(opts)
	local cli = require("winterm.cli")
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

	local label_idx = cli.parse_label_index(opts.args)
	if label_idx then
		if opts.bang then
			require("winterm.api").kill(tostring(label_idx), true, opts.count)
		else
			require("winterm.api").focus(tostring(label_idx), opts.count)
		end
		return
	end

	if cli.looks_like_index_token(sub) then
		local normalized_args = cli.normalize_index_arg(opts.args)
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
		return cli.complete_winterm(arglead, cmdline, cursorpos)
	end,
})
