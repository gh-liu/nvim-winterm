# nvim-winterm

Multi-terminal window manager for Neovim.

## Installation

### lazy.nvim

```lua
{
    "gh-liu/nvim-winterm",
    opts = {
        height = 0.3,
    },
},
```

## Configuration

### Options

- `height`: Window height as a ratio of screen lines (default `0.3`, legacy alias for `win.height`)
- `win.height`: Window height as a ratio of screen lines (default `0.3`)
- `win.position`: Split command for opening the window (default `botright`)
- `win.min_height`: Minimum window height in lines (default `1`)

Example (legacy, still supported):

```lua
{
    "gh-liu/nvim-winterm",
    opts = {
        height = 0.3,
    },
}
```

Example (new structure):

```lua
{
    "gh-liu/nvim-winterm",
    opts = {
        win = {
            height = 0.3,
            position = "botright",
            min_height = 1,
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
- Legacy: `-dir path`

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
