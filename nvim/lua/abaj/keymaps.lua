-- Common options for most keymaps
local opts = { noremap = true, silent = true }
local term_opts = { silent = true }

--Remap space as leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Modes
--   normal_mode = "n",
--   insert_mode = "i",
--   visual_mode = "v",
--   visual_block_mode = "x",
--   term_mode = "t",
--   command_mode = "c",



-- pairs
vim.keymap.set('i', '{', '{}<Left>', opts)
vim.keymap.set('i', '[', '[]<Left>', opts)
vim.keymap.set('i', '(', '()<Left>', opts)
vim.keymap.set('i', "'", "''<Left>", opts)
vim.keymap.set('i', '"', '""<Left>', opts)
vim.keymap.set('i', '$', '$$<Left>', opts)
vim.keymap.set('i', '<', '<><Left>', opts)

-- centering (there is a better way to do this...)
vim.keymap.set('n', 'j', 'jzz', opts)
vim.keymap.set('n', 'k', 'kzz', opts)
vim.keymap.set('n', 'n', 'nzzzv', opts)
vim.keymap.set('n', 'N', 'Nzzzv', opts)
vim.keymap.set('n', '<CR>', '<CR>zz', opts)
vim.keymap.set('i', '<BS>', '<BS><C-O>zz', opts)
vim.keymap.set('i', '<right>', '<right><C-O>zz', opts)
vim.keymap.set('i', '<left>', '<left><C-O>zz', opts)
vim.keymap.set('i', '<up>', '<up><C-O>zz', opts)
vim.keymap.set('i', '<down>', '<down><C-O>zz', opts)

-- tags
vim.keymap.set('n', 'go', 'g<c-]>', opts)
vim.keymap.set('v', 'go', 'g<c-]>', opts)

-- plugins
vim.keymap.set('n', '<leader>.', '<Plug>Zoom', opts)
vim.keymap.set('n', '<BS>', ':Lf<CR>', opts)
vim.keymap.set('n', '<leader><BS>', ':LfNewTab<CR>', opts)
vim.keymap.set('n', '<S-l>', ':FloatermNew lazygit<CR>', opts)

-- buffers
vim.keymap.set('n', '<leader>t', ':bnext<CR>', opts)
vim.keymap.set('n', '<leader>h', ':bprevious<CR>', opts)
vim.keymap.set('n', '<leader>x', ':bd<CR>', opts)
-- navigate splits
vim.keymap.set('n', '<Esc>b', '<C-w>h', opts) -- left
vim.keymap.set('n', '<Esc>m', '<C-w>l', opts) -- right
vim.keymap.set('n', '<Esc>w', '<C-w>j', opts) -- down
vim.keymap.set('n', '<Esc>v', '<C-w>k', opts) -- up
vim.keymap.set('n', 'z', '<S-v>', opts) -- Z for Visual Line
-- create splits
vim.keymap.set('n', '<Esc>-', '<C-w>s<C-w>j<cmd>Lf<CR>', opts)
vim.keymap.set('n', '<Esc>s', '<C-w>v<C-w>l<cmd>Lf<CR>', opts)

-- tabs
vim.keymap.set('n', '<Esc>t', ':tabn<CR>', opts)
vim.keymap.set('n', '<Esc>h', ':tabp<CR>', opts)
vim.keymap.set('n', '<Esc>x', ':tabclose<CR>', opts)
vim.keymap.set('n', '<Esc>e', ':tabnew<CR>', opts)
vim.keymap.set('n', '<Esc><S-h>', ':tabm -1<CR>', opts)
vim.keymap.set('n', '<Esc><S-t>', ':tabm +1<CR>', opts)
vim.keymap.set('n', 'gF', '<C-W>gf', opts)

-- misc
vim.keymap.set('n', '<CR>', ':noh<CR><CR>', opts)
vim.keymap.set('n', 't', 'l', opts)
vim.keymap.set('v', 't', 'l', opts)
vim.keymap.set('n', '<leader>,', 'a_<Esc>r', opts)
vim.keymap.set('n', '<leader>u', ':NvimTreeToggle<CR>', opts)
vim.keymap.set('n', '<leader>e', ':enew<CR>', opts)
vim.keymap.set('n', 'Y', '"*y', opts)

-- configs
vim.keymap.set('n', '<Esc>cv', ':e ~/.config/nvim/<CR>', opts)
vim.keymap.set('n', '<Esc>cz', ':e ~/.config/zsh/.zshrc<CR>', opts)

-- shell
vim.keymap.set('n', 'P', ':w<CR>:AsyncRun \'/Users/aayushbajaj/Google Drive/2. - code/206. - scripts/beamer\' \'%\'<CR>', opts)
-- keymap("n", "H", ":w<CR>:AsyncRun '/Users/aayushbajaj/Google Drive/2. - code/206. - scripts/handout' '%'<CR>", opts)
vim.keymap.set('n', 'H', ':w<CR>:AsyncRun lualatex % && echo % | rev | cut -c5- | rev | xargs -I{} open -a "Brave Browser Beta.app" {}.pdf<CR>', opts)
vim.keymap.set('n', 'E', ':silent ! \'/Users/aayushbajaj/Google Drive/2. - code/202. - c/bytelocker/bytelocker\' \'%\' \'$bl_pass\'<CR>:set noro<CR>', opts)


-- Resize with arrows
-- keymap("n", "<C-Up>", ":resize -2<CR>", opts)
-- keymap("n", "<C-Down>", ":resize +2<CR>", opts)
-- keymap("n", "<C-Left>", ":vertical resize -2<CR>", opts)
-- keymap("n", "<C-Right>", ":vertical resize +2<CR>", opts)
--

-- telescope
vim.keymap.set('n', '<leader>U', "<cmd>lua require'telescope.builtin'.live_grep(require('telescope.themes').get_dropdown({}))<CR>", opts)
vim.keymap.set('n', '<leader>B', "<cmd>lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({}))<CR>", opts)
vim.keymap.set('n', '<leader>F', "<cmd>lua require'telescope.builtin'.find_files(require('telescope.themes').get_dropdown({}))<CR>", opts)

-- No more vimwiki mappings
