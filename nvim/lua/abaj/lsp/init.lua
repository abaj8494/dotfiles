-- Mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local opts = {noremap = true, silent = true}
vim.keymap.set("n", "<space>e", vim.diagnostic.open_float, opts)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, opts)

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

  -- Mappings.
  -- See `:help vim.lsp.*` for documentation on any of the below functions
  local bufopts = {noremap = true, silent = true, buffer = bufnr}
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
  vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
  vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
  vim.keymap.set(
    "n",
    "<space>wl",
    function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end,
    bufopts
  )
  vim.keymap.set("n", "<space>D", vim.lsp.buf.type_definition, bufopts)
  vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
  vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
  vim.keymap.set("n", "<space>f", vim.lsp.buf.formatting, bufopts)
  -- vim.keymap.set('n', '<space>lg', vim.lsp.buf.formatting, bufopts)
  --
  vim.api.nvim_create_autocmd(
    "CursorHold",
    {
      buffer = bufnr,
      callback = function()
        local opts = {
          focusable = false,
          close_events = {"BufLeave", "CursorMoved", "InsertEnter", "FocusLost"},
          border = "rounded",
          source = "always",
          prefix = " ",
          scope = "cursor"
        }
        vim.diagnostic.open_float(nil, opts)
      end
    }
  )
  if client.name == "tsserver" then
    client.server_capabilities.document_formatting = false -- 0.7 and earlier
  -- client.server_capabilities.documentFormattingProvider = false -- 0.8 and later
  end
end

-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

local lsp_flags = {
  -- This is the default in Nvim 0.7+
  debounce_text_changes = nil
}



vim.lsp.handlers["textDocument/publishDiagnostics"] =
  vim.lsp.with(
  vim.lsp.diagnostic.on_publish_diagnostics,
  {
    -- Enable underline, use default values
    underline = true,
    -- Enable virtual text, override spacing to 4
    virtual_text = {
      spacing = 4
      -- prefix = '~',
    },
    -- Use a function to dynamically turn signs off
    -- and on, using buffer local variables
    signs = function(bufnr, client_id)
      local ok, result = pcall(vim.api.nvim_buf_get_var, bufnr, "show_signs")
      -- No buffer local variable set, so just enable by default
      if not ok then
        return true
      end

      return result
    end,
    -- Disable a feature
    update_in_insert = false
    --virtual_text = true
  }
)

vim.cmd [[autocmd! CursorHold,CursorHoldI * lua vim.diagnostic.open_float(nil, {focus=false, scope="cursor"})]]

-- Format on save
--vim.cmd [[
--    autocmd BufWritePre *.java lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.js lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.ts lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.tsx lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.jsx lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.rs lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.py lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.cs lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.php lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.tex lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.py lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.json lua vim.lsp.buf.formatting_sync(nil, 1000)
--    autocmd BufWritePre *.svelte lua vim.lsp.buf.formatting_sync(nil, 1000)
--]]



-- Enable codelens
vim.cmd [[
    autocmd BufEnter,CursorHold,InsertLeave <buffer> lua vim.lsp.codelens.refresh()
]]

-- Enable eslint and prettier
require("null-ls")
require'lspconfig'.pyright.setup{}
require'lspconfig'.texlab.setup{}
require("mason").setup()
require("mason-lspconfig").setup()
