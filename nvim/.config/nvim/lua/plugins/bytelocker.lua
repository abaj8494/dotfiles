return {
	"abaj8494/bytelocker",
	config = function()
		require("bytelocker").setup({
			setup_keymaps = true, -- Optional: set up default keymaps
			cipher = "shift", -- Optional: pre-select cipher ("shift", "xor", "caesar")
			-- If not specified, you'll be prompted when first using the plugin
		})
	end,
}
