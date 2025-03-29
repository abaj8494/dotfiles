require "abaj.options"
require "abaj.keymaps"
require "abaj.plugins"
require "abaj.cmp"
require "abaj.lsp"
require "abaj.latex"
require "abaj.luasnip"
require "abaj.mod"
require "abaj.ntree"

-- latex
vim.g.vimtex_view_general_viewer = 'open -a Brave Browser Beta.app'
vim.g.vimtex_view_general_options = '@pdf'

-- Set Tokyo Night theme
vim.cmd("colorscheme tokyonight")
vim.g.transparent_enabled = false
vim.g.OxfDictionary_app_id = 'd9ac7995'
vim.g.OxfDictionary_app_key = 'c3e81fe9c9bd494a3efb4ef2a6a1ae76'

-- lf
vim.g.lf_replace_netrw = 1
vim.g.floaterm_height = 0.95
vim.g.floaterm_width = 0.95
vim.g.lf_map_keys = 0

-- Auto-start LF when Neovim opens
local lf_auto_group = vim.api.nvim_create_augroup("LfAutoStart", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Only start LF if no file was specified or a directory was specified
    local argv = vim.fn.argv()
    if #argv == 0 or (vim.fn.isdirectory(argv[1]) == 1) then
      vim.cmd("Lf")
    end
  end,
  group = lf_auto_group,
})

-- quickfixlist keymaps
vim.keymap.set('n', '<leader>G', ':cprev<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>C', ':cnext<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>Q', ':cexpr []<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>q', ':call ToggleList("Quickfix List", "c")<CR>', { noremap = true, silent = true })

-- functions for buffer and quickfix list operations
-- GetBufferList function
_G.GetBufferList = function()
  local buffers = {}
  for buffer = 1, vim.fn.bufnr('$') do
    if vim.fn.buflisted(buffer) == 1 then
      table.insert(buffers, buffer)
    end
  end
  return buffers
end

-- ToggleList function
_G.ToggleList = function(bufname, pfx)
  local buffers = GetBufferList()
  local pattern = bufname
  
  -- Check if the buffer is open
  for _, bufnum in ipairs(buffers) do
    local buftype = vim.fn.getbufvar(bufnum, '&buftype')
    if buftype == (pfx == 'c' and 'quickfix' or 'locationlist') then
      vim.cmd(pfx..'close')
      return
    end
  end
  
  -- Check if the location list is empty
  if pfx == 'l' and vim.tbl_isempty(vim.fn.getloclist(0)) then
    vim.api.nvim_echo({{bufname.." is Empty.", "ErrorMsg"}}, true, {})
    return
  end
  
  -- Open the list
  local winnr = vim.fn.winnr()
  vim.cmd(pfx..'open')
  if vim.fn.winnr() ~= winnr then
    vim.cmd('wincmd p')
  end
end

-- Register the Vim function wrappers for backward compatibility
vim.cmd([[
function! GetBufferList()
  return luaeval('GetBufferList()')
endfunction

function! ToggleList(bufname, pfx)
  call luaeval('ToggleList(_A[1], _A[2])', [a:bufname, a:pfx])
endfunction
]])
