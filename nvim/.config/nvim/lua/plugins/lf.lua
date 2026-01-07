return {
	"voldikss/vim-floaterm",
	config = function()
		vim.g.floaterm_height = 0.95
		vim.g.floaterm_width = 0.95
		vim.g.floaterm_autoclose = 1
		vim.g.floaterm_opener = "edit" -- or "drop"
	end,
	keys = {
		{
			"<BS>",
			function()
				local height = vim.g.floaterm_height or 0.95
				local width = vim.g.floaterm_width or 0.95

				local current_path
				if vim.fn.expand("%:p:h") ~= "" then
					current_path = vim.fn.expand("%:p:h")
				else
					current_path = vim.fn.getcwd()
				end

				local cmd = string.format(
					"FloatermNew --height=%s --width=%s --title=lf lf %s",
					height,
					width,
					vim.fn.shellescape(current_path)
				)

				vim.cmd(cmd)
			end,
			desc = "Open lf",
			mode = "n", -- explicitly set to normal mode
		},
	},
}
