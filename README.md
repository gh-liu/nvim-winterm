# nvim-winterm

Multi-terminal window manager.

<img width="2032" height="1162" alt="Screenshot 2026-01-21 at 11 26 33" src="https://github.com/user-attachments/assets/841a1a0a-56da-4c1f-9521-9b470f288459" />

## Installation

### lazy.nvim

```lua
{
    "gh-liu/nvim-winterm",
    opts = {
        win = {
            height = 0.3,
        },
    },
},
```

## Configuration

### Options

- `win.height`: Window height as a ratio of screen lines (default `0.3`)

Example:

```lua
{
    "gh-liu/nvim-winterm",
    opts = {
        win = {
            height = 0.3,
        },
    },
}
```

## Highlight

Winbar uses its own highlight groups, linked to TabLine by default:

- `WintermWinbar` -> `TabLine`
- `WintermWinbarSel` -> `TabLineSel`

## Commands

- `:Winterm`: Toggle the window (opens a shell the first time)
- `:Winterm {cmd}`: Create a terminal running `{cmd}`
- `:Winterm -dir={path} {cmd}`: Create a terminal in `{path}` (default uses `getcwd()`)
- `:Winterm [N]` or `:[N]Winterm`: Focus terminal by index
- `:Winterm! [N]` or `:[N]Winterm!`: Kill terminal (force with `!`)

For relative navigation, `+N/-N` works with focus/kill arguments (e.g. `:Winterm -1` or `:Winterm! +1`). For absolute index, pass it as an argument or a count (e.g. `:Winterm 3` or `:3Winterm`).

`-dir` supports these forms:

- `-dir=path`
- `-dir="path with spaces"`
- `-dir='path with spaces'`

## Lua API

`run()` returns a stable term object (identified by `bufnr`). Use `list()` to get all terms.

```lua
local winterm = require("winterm")

local term = winterm.run("npm run dev", { focus = false })
if term then
	term:focus()
end

vim.ui.select(winterm.list(), {
	prompt = "Winterm terminals",
	format_item = function(item)
		return string.format("%s  (%s)", item.cmd, item.cwd or "")
	end,
}, function(choice)
	if choice then
		choice:focus()
	end
end)
```
