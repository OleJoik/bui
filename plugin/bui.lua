if vim.g.loaded_bui_plugin == 1 then
  return
end
vim.g.loaded_bui_plugin = 1

require("bui").setup()
