local fn = vim.fn

-- Automatically install packer
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
if fn.empty(fn.glob(install_path)) > 0 then
	PACKER_BOOTSTRAP = fn.system({
		"git",
		"clone",
		"--depth",
		"1",
		"https://github.com/wbthomason/packer.nvim",
		install_path,
	})
	print("Installing packer close and reopen Neovim...")
	vim.cmd([[packadd packer.nvim]])
end

-- Create autocmd group for packer
local packer_group = vim.api.nvim_create_augroup("packer_user_config", { clear = true })

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "plugins.lua",
  command = "source <afile> | PackerSync",
  group = packer_group,
})

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
	return
end

-- Have packer use a popup window
packer.init({
	display = {
		open_fn = function()
			return require("packer.util").float({ border = "rounded" })
		end,
	},
})

-- Install your plugins here
return packer.startup(function(use)

    use 'wbthomason/packer.nvim'
    use {
        'kyazdani42/nvim-tree.lua',
        requires = {
            'kyazdani42/nvim-web-devicons', -- optional, for file icons
        }
    }
    use { 
        'junegunn/fzf', 
        run = function() vim.fn['fzf#install']() end 
    }
    use { 'junegunn/fzf.vim' }
    use 'Mathijs-Bakker/zoom-vim'
    use 'tpope/vim-surround'
    use 'nvim-lua/plenary.nvim'
    use 'nvim-telescope/telescope.nvim'
    use 'skywind3000/asyncrun.vim'
    use 'ptzz/lf.vim'
    use 'voldikss/vim-floaterm'
    use 'xiyaowong/nvim-transparent'
    use 'wellle/targets.vim'
    use {
        'folke/tokyonight.nvim',
        config = function()
            require('tokyonight').setup({
                style = "night",
                transparent = true,
                terminal_colors = true,
                styles = {
                    comments = { italic = true },
                    keywords = { italic = true },
                    functions = {},
                    variables = {},
                    sidebars = "dark",
                    floats = "dark",
                },
                sidebars = { "qf", "help", "terminal", "packer", "NvimTree" },
                hide_inactive_statusline = false,
            })
        end
    }

    -- lsp
    use {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "neovim/nvim-lspconfig",
        "jay-babu/mason-null-ls.nvim",
        "jose-elias-alvarez/null-ls.nvim",
        -- java
        'mfussenegger/nvim-jdtls'
    }

-- cmp
    use "hrsh7th/nvim-cmp"
	use "hrsh7th/cmp-buffer"
	use "hrsh7th/cmp-path"
    use "hrsh7th/cmp-cmdline"
	use "hrsh7th/cmp-nvim-lua"
	use "hrsh7th/cmp-nvim-lsp"

	use "saadparwaiz1/cmp_luasnip"
    use "L3MON4D3/LuaSnip" --snippet engine
    use "onsails/lspkind.nvim"
    use "ray-x/lsp_signature.nvim"
    
    -- cscope
    use 'dhananjaylatkar/cscope_maps.nvim' -- cscope keymaps
    
    -- texstuff
    use 'lervag/vimtex'

    require('cscope_maps') -- load cscope maps

	-- Automatically set up your configuration after cloning packer.nvim
	-- Put this at the end after all plugins
	if PACKER_BOOTSTRAP then
		require("packer").sync()
	end
end)

