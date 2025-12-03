-- Source zprofile (though better to let your shell do this)
vim.cmd('source ~/.config/zsh/.zprofile')

-- Tab and shift tab key mappings
vim.keymap.set('v', '<Tab>', '>gv', { noremap = true })
vim.keymap.set('v', '<S-Tab>', '<gv', { noremap = true })
vim.keymap.set('n', '<S-Tab>', '<<', { noremap = true })
vim.keymap.set('i', '<S-Tab>', '<C-d>', { noremap = true })

-- Terminal cursor shape settings
vim.opt.guicursor = {
  'n-v-c:block-Cursor/lCursor',
  'i-ci:ver25-Cursor/lCursor',
  'r:hor20-Cursor/lCursor',
}

-- Ensure terminal connections are fast
vim.opt.ttimeout = true
vim.opt.ttimeoutlen = 1
vim.opt.ttyfast = true

-- Python file mappings
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.keymap.set('n', '<leader>r', ':w<CR>:!clear;python3 %<CR>', { noremap = true, buffer = true })
  end,
})

-- LaTeX settings
vim.g.vimtex_view_general_viewer = 'zathura' 