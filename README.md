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

- `height`: Window height as a ratio of screen lines (default `0.3`)
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
