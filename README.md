# bui

A tiny reactive UI demo for Neovim, packaged as a standard plugin.

## Install (Neovim 0.12+ builtin package manager)

```lua
vim.pack.add({
  { src = "https://github.com/<you>/bui" },
})
```

Then open it with:

```vim
:BuiOpen
```

## Layout

- `plugin/bui.lua`: plugin entrypoint loaded by Neovim.
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
