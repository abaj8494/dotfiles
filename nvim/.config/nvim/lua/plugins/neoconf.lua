return {
	{
		"folke/neoconf.nvim",
		-- Must load before lspconfig
		priority = 100,
		lazy = false,
		opts = {
			-- Import settings from VSCode's settings.json
			import = {
				vscode = true,
				coc = false,
				nlsp = false,
			},
			-- Live reload when .neoconf.json changes
			live_reload = true,
			-- Filetype to use for .neoconf.json files
			filetype_jsonc = true,
			-- Array of plugins to import settings from
			plugins = {
				-- Configures lspconfig servers
				lspconfig = {
					enabled = true,
				},
				-- Configures jsonls to get completion in .neoconf.json
				jsonls = {
					enabled = true,
					configured_servers_only = true,
				},
				-- Configures lua_ls to get workspace library
				lua_ls = {
					enabled_for_neovim_config = true,
					enabled = false,
				},
			},
		},
	},
}
