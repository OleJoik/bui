# bui

A tiny reactive UI demo for Neovim.

## Install (Neovim 0.12+ builtin package manager)

```lua
vim.pack.add({
  { src = "https://github.com/<you>/bui" },
})

require("bui").setup()
```

Then open it with:

```vim
:BuiOpen
```

## Layout

- `lua/bui/init.lua`: module implementation and public API.

## API

```lua
require("bui").open()
```

or:

```lua
require("bui").setup({
  create_command = true, -- default
})
```
