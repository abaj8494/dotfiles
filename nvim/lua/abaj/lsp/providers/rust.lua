function load(args)
  require "lspconfig".rls.setup {
    capabilities = args.capabilities,
    on_attach = args.on_attach,
    flags = args.flags
  }
end

return {
  load = load
}
