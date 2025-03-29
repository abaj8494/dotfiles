-- Disable netrw to avoid conflicts
vim.g.loaded = 1
vim.g.loaded_netrwPlugin = 1

-- Configure nvim-tree
require("nvim-tree").setup({
  sort_by = "case_sensitive",
  view = {
    adaptive_size = true,
    mappings = {
      list = {
        { key = "u", action = "dir_up" },
      },
    },
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = false, -- Show dotfiles
  },
})
