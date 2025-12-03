-- Updated LSP config compatible with modern Neovim API

-- Mappings.
local opts = { noremap = true, silent = true }
vim.keymap.set("n", "<space>e", vim.diagnostic.open_float, opts)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, opts)

local on_attach = function(client, bufnr)
  vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

  local bufopts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
  vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
  vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
  vim.keymap.set("n", "<space>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, bufopts)
  vim.keymap.set("n", "<space>D", vim.lsp.buf.type_definition, bufopts)
  vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
  vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
  vim.keymap.set("n", "<space>f", function() vim.lsp.buf.format { async = true } end, bufopts)

  vim.api.nvim_create_autocmd("CursorHold", {
    buffer = bufnr,
    callback = function()
      local float_opts = {
        focusable = false,
        close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
        border = "rounded",
        source = "always",
        prefix = " ",
        scope = "cursor"
      }
      vim.diagnostic.open_float(nil, float_opts)
    end
  })

  if client.name == "tsserver" then
    client.server_capabilities.documentFormattingProvider = false
  end
end

local capabilities = require("cmp_nvim_lsp").default_capabilities()

local lsp_flags = {
  debounce_text_changes = 150,
}

vim.diagnostic.config({
  underline = true,
  virtual_text = {
    spacing = 4,
  },
  signs = true,
  update_in_insert = false,
  severity_sort = true,
})

vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
  callback = function()
    vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
  end
})

vim.api.nvim_create_autocmd({"BufEnter", "CursorHold", "InsertLeave"}, {
  callback = function()
    pcall(vim.lsp.codelens.refresh)
  end
})

require("mason").setup {
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    }
  }
}

require("mason-lspconfig").setup {
  ensure_installed = {
    "lua_ls", "pyright", "texlab", "rust_analyzer", "svelte",
    "intelephense", "cssls", "html", "jdtls"
  },
  automatic_installation = true,
}

require("null-ls").setup {}

local lspconfig = require("lspconfig")
local mason_lspconfig = require("mason-lspconfig")

-- Get list of installed servers
mason_lspconfig.setup()
local servers = mason_lspconfig.get_installed_servers()

for _, server_name in ipairs(servers) do
  if server_name == "lua_ls" then
    lspconfig.lua_ls.setup {
      on_attach = on_attach,
      capabilities = capabilities,
      flags = lsp_flags,
      settings = {
        Lua = {
          diagnostics = {
            globals = { "vim" }
          },
          workspace = {
            library = vim.api.nvim_get_runtime_file("", true),
            checkThirdParty = false
          },
          telemetry = { enable = false }
        }
      }
    }
  else
    lspconfig[server_name].setup {
      on_attach = on_attach,
      capabilities = capabilities,
      flags = lsp_flags,
    }
  end
end

