local null_ls = require("null-ls")

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics
local code_actions = null_ls.builtins.code_actions

null_ls.setup({
  debug = false,
  sources = {
    formatting.prettier,
    formatting.stylua,
    formatting.black,
    diagnostics.eslint_d,
    code_actions.eslint_d,
  }
})

-- Setup Mason-null-ls
require("mason-null-ls").setup({
  ensure_installed = {
    "prettier",
    "stylua",
    "black",
    "eslint_d",
  },
  automatic_installation = true,
  automatic_setup = true,
})
