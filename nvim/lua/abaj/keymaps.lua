local opts = { noremap = true, silent = true }

local term_opts = { silent = true }

-- Shorten function name
local keymap = vim.api.nvim_set_keymap

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
keymap("i", "{", "{}<Left>", opts)
keymap("i", "[", "[]<Left>", opts)
keymap("i", "(", "()<Left>", opts)
keymap("i", "'", "''<Left>", opts)
keymap("i", "\"", "\"\"<Left>", opts)
keymap("i", "$", "$$<Left>", opts)
keymap("i", "<", "<><Left>", opts)

-- centering (there is a better way to do this...)
keymap("n", "j", "jzz", opts)
keymap("n", "k", "kzz", opts)
keymap("n", "n", "nzzzv", opts)
keymap("n", "N", "Nzzzv", opts)
keymap("n", "<CR>", "<CR>zz", opts)
keymap("i", "<BS>", "<BS><C-O>zz", opts)
keymap("i", "<right>", "<right><C-O>zz", opts)
keymap("i", "<left>", "<left><C-O>zz", opts)
keymap("i", "<up>", "<up><C-O>zz", opts)
keymap("i", "<down>", "<down><C-O>zz", opts)

-- tags
keymap("n", "go", "g<c-]>", opts)
keymap("v", "go", "g<c-]>", opts)

-- plugins
keymap("n", "<leader>.", "<Plug>Zoom", opts)
keymap("n", "<BS>", ":Lf<CR>", opts)
keymap("n", "<leader><BS>", ":LfNewTab<CR>", opts)
keymap("n", "<S-l>", ":FloatermNew lazygit<CR>", opts)

-- buffers
keymap("n", "<leader>t", ":bnext<CR>", opts)
keymap("n", "<leader>h", ":bprevious<CR>", opts)
keymap("n", "<leader>x", ":bd<CR>", opts)
-- navigate splits
keymap("n", "<Esc>b", "<C-w>h", opts) -- left
keymap("n", "<Esc>m", "<C-w>l", opts) -- right
keymap("n", "<Esc>w", "<C-w>j", opts) -- down
keymap("n", "<Esc>v", "<C-w>k", opts) -- up
keymap("n", "z", "<S-v>", opts) -- Z for Visual Line
-- create splits
keymap("n", "<Esc>-", "<C-w>s<C-w>j<cmd>Lf<CR>", opts)
keymap("n", "<Esc>s", "<C-w>v<C-w>l<cmd>Lf<CR>", opts)

-- tabs
keymap("n", "<Esc>t", ":tabn<CR>", opts)
keymap("n", "<Esc>h", ":tabp<CR>", opts)
keymap("n", "<Esc>x", ":tabclose<CR>", opts)
keymap("n", "<Esc>e", ":tabnew<CR>", opts)
keymap("n", "<Esc><S-h>", ":tabm -1<CR>", opts)
keymap("n", "<Esc><S-t>", ":tabm +1<CR>", opts)
keymap("n", "gF", "<C-W>gf", opts)

-- misc
keymap("n", "<CR>", ":noh<CR><CR>", opts)
keymap("n", "t", "l", opts)
keymap("v", "t", "l", opts)
keymap("n", "<leader>,", "a_<Esc>r", opts)
keymap("n", "<leader>u", ":NERDTreeToggle<CR>", opts)
keymap("n", "<leader>e", ":enew<CR>", opts)
keymap("n", "Y", "\"*y", opts)

-- configs
keymap("n", "<Esc>cv", ":e ~/.config/nvim/<CR>", opts)
keymap("n", "<Esc>cz", ":e ~/.config/zsh/.zshrc<CR>", opts)

-- shell
keymap("n", "P", ":w<CR>:AsyncRun '/Users/aayushbajaj/Google Drive/2. - code/206. - scripts/beamer' '%'<CR>", opts)
-- keymap("n", "H", ":w<CR>:AsyncRun '/Users/aayushbajaj/Google Drive/2. - code/206. - scripts/handout' '%'<CR>", opts)
keymap("n", "H", ":w<CR>:AsyncRun lualatex % && echo % | rev | cut -c5- | rev | xargs -I{} open -a \"Brave Browser Beta.app\" {}.pdf<CR>", opts)
keymap("n", "E", ":silent ! '/Users/aayushbajaj/Google Drive/2. - code/202. - c/bytelocker/bytelocker' '%' '$bl_pass'<CR>:set noro<CR>", opts)


-- Resize with arrows
-- keymap("n", "<C-Up>", ":resize -2<CR>", opts)
-- keymap("n", "<C-Down>", ":resize +2<CR>", opts)
-- keymap("n", "<C-Left>", ":vertical resize -2<CR>", opts)
-- keymap("n", "<C-Right>", ":vertical resize +2<CR>", opts)
--

-- telescope
keymap("n", "<leader>U", "<cmd>lua require'telescope.builtin'.live_grep(require('telescope.themes').get_dropdown({}))<CR>", opts)
keymap("n", "<leader>B", "<cmd>lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({}))<CR>", opts)
keymap("n", "<leader>F", "<cmd>lua require'telescope.builtin'.find_files(require('telescope.themes').get_dropdown({}))<CR>", opts)

-- ultisnips
-- keymap("n", "<leader>S", ":Snippets<CR>", opts)

-- cscope
-- these are loaded as a plugin. see ./plugins.lua
-- <leader>cs	find all references to the token under cursor
-- <leader>cg	find global definition(s) of the token under cursor
-- <leader>cc	find all calls to the function name under cursor
-- <leader>ct	find all instances of the text under cursor
-- <leader>ce	egrep search for the word under cursor
-- <leader>cf	open the filename under cursor
-- <leader>ci	find files that include the filename under cursor
-- <leader>cd	find functions that function under cursor calls
-- <leader>ca	find places where this symbol is assigned a value
