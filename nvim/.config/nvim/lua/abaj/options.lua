local options = {
	colorcolumn = "80",
	undofile = true,
	hlsearch = true,						 -- search highlighting
	showcmd = true,							 -- visual mode character count
	incsearch = true,						 -- partial search
	ignorecase = true,						 -- case insensitive search
	smartcase = true,
	nu = true,								 -- line numbers on
	rnu = true, 							 -- relative numbers on
	splitright = true,						 -- split new window to right
	wrap = true,							 -- does not wrap text
	swapfile = true,
	shiftwidth = 4,							 -- indentation
	tabstop = 4,
	softtabstop = 4,
	expandtab = true,
	smartindent = true,
	hidden = true,							 -- removes 'save buffer to exit'
	ttimeout = true,						 -- fix ssh tmux aesthetic
	ttimeoutlen = 1,
	ttyfast = true,
	backup = false,                          -- creates a backup file
	clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
	cmdheight = 2,                           -- more space in the neovim command line for displaying messages
	conceallevel = 0,                        -- so that `` is visible in markdown files
	fileencoding = "utf-8",                  -- the encoding written to a file
	mouse = "a",                             -- allow the mouse to be used in neovim
	pumheight = 10,                          -- pop up menu height
	showtabline = 2,                         -- always show tabs
	scrolloff = 8,                           -- is one of my fav
	sidescrolloff = 8,
	guifont = "monospace:h17",               -- the font used in graphical neovim applications
	whichwrap = vim.opt.whichwrap:append("<,>,[,],h,l"), -- Allow specified keys to move to the previous/next line when at the start/end
}

vim.opt.shortmess:append "c"

for k, v in pairs(options) do
  vim.opt[k] = v
end

-- Ensure mouse works correctly
vim.opt.mouse:append("a")
