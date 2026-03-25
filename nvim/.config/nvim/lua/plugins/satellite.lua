return {
  "lewis6991/satellite.nvim",
  event = "VeryLazy",
  opts = {
    winblend = 50,
    handlers = {
      cursor = { enable = true },
      search = { enable = true },
      diagnostic = { enable = true },
      gitsigns = { enable = true },
      marks = { enable = true },
    },
  },
}
