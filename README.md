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

- `:Winterm`: Toggle the window
- `:Winterm open|close`: Open/close the window
- `:Winterm run {cmd}`: Create a terminal
- `:Winterm kill[!] [N:CMD]`: Close a terminal (force with `!`)
- `:Winterm focus [N:CMD]`: Focus a terminal by index

For relative navigation, `+N/-N` works only with `:Winterm focus` as arguments (e.g. `:Winterm focus -1`). For absolute index, pass it as an argument (e.g. `:Winterm focus 3`).
