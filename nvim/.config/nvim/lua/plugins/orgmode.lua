return {
	{
		"nvim-orgmode/orgmode",
		event = "VeryLazy",
		ft = { "org" },
		config = function()
			require("orgmode").setup({
				org_startup_folded = "content",
				org_hide_leading_stars = true,
			})
		end,
	},
}
