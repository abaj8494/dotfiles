-- Automatically generated packer.nvim plugin loader code

if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Invalid Neovim version for packer.nvim! | echohl None"')
  return
end

vim.api.nvim_command('packadd packer.nvim')

local no_errors, error_msg = pcall(function()

_G._packer = _G._packer or {}
_G._packer.inside_compile = true

local time
local profile_info
local should_profile = false
if should_profile then
  local hrtime = vim.loop.hrtime
  profile_info = {}
  time = function(chunk, start)
    if start then
      profile_info[chunk] = hrtime()
    else
      profile_info[chunk] = (hrtime() - profile_info[chunk]) / 1e6
    end
  end
else
  time = function(chunk, start) end
end

local function save_profiles(threshold)
  local sorted_times = {}
  for chunk_name, time_taken in pairs(profile_info) do
    sorted_times[#sorted_times + 1] = {chunk_name, time_taken}
  end
  table.sort(sorted_times, function(a, b) return a[2] > b[2] end)
  local results = {}
  for i, elem in ipairs(sorted_times) do
    if not threshold or threshold and elem[2] > threshold then
      results[i] = elem[1] .. ' took ' .. elem[2] .. 'ms'
    end
  end
  if threshold then
    table.insert(results, '(Only showing plugins that took longer than ' .. threshold .. ' ms ' .. 'to load)')
  end

  _G._packer.profile_output = results
end

time([[Luarocks path setup]], true)
local package_path_str = "/Users/aayushbajaj/.cache/nvim/packer_hererocks/2.1.1748459687/share/lua/5.1/?.lua;/Users/aayushbajaj/.cache/nvim/packer_hererocks/2.1.1748459687/share/lua/5.1/?/init.lua;/Users/aayushbajaj/.cache/nvim/packer_hererocks/2.1.1748459687/lib/luarocks/rocks-5.1/?.lua;/Users/aayushbajaj/.cache/nvim/packer_hererocks/2.1.1748459687/lib/luarocks/rocks-5.1/?/init.lua"
local install_cpath_pattern = "/Users/aayushbajaj/.cache/nvim/packer_hererocks/2.1.1748459687/lib/lua/5.1/?.so"
if not string.find(package.path, package_path_str, 1, true) then
  package.path = package.path .. ';' .. package_path_str
end

if not string.find(package.cpath, install_cpath_pattern, 1, true) then
  package.cpath = package.cpath .. ';' .. install_cpath_pattern
end

time([[Luarocks path setup]], false)
time([[try_loadstring definition]], true)
local function try_loadstring(s, component, name)
  local success, result = pcall(loadstring(s), name, _G.packer_plugins[name])
  if not success then
    vim.schedule(function()
      vim.api.nvim_notify('packer.nvim: Error running ' .. component .. ' for ' .. name .. ': ' .. result, vim.log.levels.ERROR, {})
    end)
  end
  return result
end

time([[try_loadstring definition]], false)
time([[Defining packer_plugins]], true)
_G.packer_plugins = {
  LuaSnip = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/LuaSnip",
    url = "https://github.com/L3MON4D3/LuaSnip"
  },
  ["asyncrun.vim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/asyncrun.vim",
    url = "https://github.com/skywind3000/asyncrun.vim"
  },
  bytelocker = {
    config = { "\27LJ\2\nY\0\0\3\0\4\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0B\0\2\1K\0\1\0\1\0\2\18setup_keymaps\2\vcipher\bxor\nsetup\15bytelocker\frequire\0" },
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/bytelocker",
    url = "https://github.com/abaj8494/bytelocker"
  },
  ["cmp-buffer"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp-buffer",
    url = "https://github.com/hrsh7th/cmp-buffer"
  },
  ["cmp-cmdline"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp-cmdline",
    url = "https://github.com/hrsh7th/cmp-cmdline"
  },
  ["cmp-nvim-lsp"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp-nvim-lsp",
    url = "https://github.com/hrsh7th/cmp-nvim-lsp"
  },
  ["cmp-nvim-lua"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp-nvim-lua",
    url = "https://github.com/hrsh7th/cmp-nvim-lua"
  },
  ["cmp-path"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp-path",
    url = "https://github.com/hrsh7th/cmp-path"
  },
  cmp_luasnip = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cmp_luasnip",
    url = "https://github.com/saadparwaiz1/cmp_luasnip"
  },
  ["cscope_maps.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/cscope_maps.nvim",
    url = "https://github.com/dhananjaylatkar/cscope_maps.nvim"
  },
  fzf = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/fzf",
    url = "https://github.com/junegunn/fzf"
  },
  ["fzf.vim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/fzf.vim",
    url = "https://github.com/junegunn/fzf.vim"
  },
  ["leetcode.nvim"] = {
    config = { "\27LJ\2\nç\a\0\0\a\0&\00036\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\4\0=\3\5\0025\3\v\0006\4\6\0009\4\a\0049\4\b\4'\6\t\0B\4\2\2'\5\n\0&\4\5\4=\4\f\0036\4\6\0009\4\a\0049\4\b\4'\6\r\0B\4\2\2'\5\n\0&\4\5\4=\4\r\3=\3\14\0025\3\15\0=\3\16\0025\3\17\0=\3\r\0025\3\18\0=\3\19\0025\3\20\0005\4\21\0=\4\22\0035\4\23\0=\4\24\0035\4\25\0=\4\26\3=\3\27\0025\3\28\0=\3\29\0025\3\30\0=\3\31\0025\3!\0005\4 \0=\4\"\0035\4#\0=\4$\3=\3%\2B\0\2\1K\0\1\0\tkeys\fconfirm\1\2\0\0\t<CR>\vtoggle\1\0\6\17use_testcase\6U\17focus_result\6L\20reset_testcases\6r\fconfirm\0\vtoggle\0\20focus_testcases\6H\1\2\0\0\6q\vpicker\1\0\1\rprovider\14telescope\16description\1\0\3\nwidth\b40%\15show_stats\2\rposition\tleft\fconsole\rtestcase\1\0\2\14virt_text\2\tsize\b40%\vresult\1\0\1\tsize\b60%\tsize\1\0\2\nwidth\b90%\vheight\b75%\1\0\5\20open_on_runcode\2\tsize\0\rtestcase\0\vresult\0\bdir\brow\veditor\1\0\2\17fold_imports\2\24reset_previous_code\2\1\0\1\20update_interval\3Äı$\fplugins\1\0\1\19non_standalone\1\fstorage\ncache\thome\1\0\2\ncache\0\thome\0\14/leetcode\tdata\fstdpath\afn\bvim\acn\1\0\3\23translate_problems\2\15translator\2\fenabled\1\1\0\r\acn\0\fconsole\0\barg\18leetcode.nvim\18image_support\1\veditor\0\vpicker\0\flogging\2\16description\0\fplugins\0\ncache\0\tlang\bcpp\fstorage\0\tkeys\0\nsetup\rleetcode\frequire\0" },
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/leetcode.nvim",
    url = "https://github.com/kawre/leetcode.nvim"
  },
  ["lf.vim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/lf.vim",
    url = "https://github.com/ptzz/lf.vim"
  },
  ["lsp_signature.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/lsp_signature.nvim",
    url = "https://github.com/ray-x/lsp_signature.nvim"
  },
  ["lspkind.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/lspkind.nvim",
    url = "https://github.com/onsails/lspkind.nvim"
  },
  ["mason-lspconfig.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/mason-lspconfig.nvim",
    url = "https://github.com/williamboman/mason-lspconfig.nvim"
  },
  ["mason-null-ls.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/mason-null-ls.nvim",
    url = "https://github.com/jay-babu/mason-null-ls.nvim"
  },
  ["mason.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/mason.nvim",
    url = "https://github.com/williamboman/mason.nvim"
  },
  ["nui.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nui.nvim",
    url = "https://github.com/MunifTanjim/nui.nvim"
  },
  ["null-ls.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/null-ls.nvim",
    url = "https://github.com/jose-elias-alvarez/null-ls.nvim"
  },
  ["nvim-cmp"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nvim-cmp",
    url = "https://github.com/hrsh7th/nvim-cmp"
  },
  ["nvim-jdtls"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nvim-jdtls",
    url = "https://github.com/mfussenegger/nvim-jdtls"
  },
  ["nvim-lspconfig"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nvim-lspconfig",
    url = "https://github.com/neovim/nvim-lspconfig"
  },
  ["nvim-transparent"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nvim-transparent",
    url = "https://github.com/xiyaowong/nvim-transparent"
  },
  ["nvim-treesitter"] = {
    config = { "\27LJ\2\n˘\1\0\0\4\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\0025\3\6\0=\3\a\0025\3\b\0=\3\t\2B\0\2\1K\0\1\0\14highlight\1\0\1\venable\2\vindent\1\0\1\venable\2\21ensure_installed\1\0\3\vindent\0\14highlight\0\21ensure_installed\0\1\n\0\0\6c\bcpp\blua\vpython\ago\15javascript\15typescript\trust\thtml\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter"
  },
  ["packer.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/packer.nvim",
    url = "https://github.com/wbthomason/packer.nvim"
  },
  ["plenary.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim"
  },
  ["targets.vim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/targets.vim",
    url = "https://github.com/wellle/targets.vim"
  },
  ["telescope.nvim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/telescope.nvim",
    url = "https://github.com/nvim-telescope/telescope.nvim"
  },
  ["tokyonight.nvim"] = {
    config = { "\27LJ\2\nÙ\2\0\0\5\0\14\0\0196\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\5\0005\4\4\0=\4\6\0035\4\a\0=\4\b\0034\4\0\0=\4\t\0034\4\0\0=\4\n\3=\3\v\0025\3\f\0=\3\r\2B\0\2\1K\0\1\0\rsidebars\1\5\0\0\aqf\thelp\rterminal\vpacker\vstyles\14variables\14functions\rkeywords\1\0\1\vitalic\2\rcomments\1\0\6\rkeywords\0\rcomments\0\vfloats\tdark\rsidebars\tdark\14variables\0\14functions\0\1\0\1\vitalic\2\1\0\6\29hide_inactive_statusline\1\rsidebars\0\vstyles\0\20terminal_colors\2\16transparent\2\nstyle\nnight\nsetup\15tokyonight\frequire\0" },
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/tokyonight.nvim",
    url = "https://github.com/folke/tokyonight.nvim"
  },
  ["vim-floaterm"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/vim-floaterm",
    url = "https://github.com/voldikss/vim-floaterm"
  },
  ["vim-surround"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/vim-surround",
    url = "https://github.com/tpope/vim-surround"
  },
  vimtex = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/vimtex",
    url = "https://github.com/lervag/vimtex"
  },
  ["zoom-vim"] = {
    loaded = true,
    path = "/Users/aayushbajaj/.local/share/nvim/site/pack/packer/start/zoom-vim",
    url = "https://github.com/Mathijs-Bakker/zoom-vim"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\n˘\1\0\0\4\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\0025\3\6\0=\3\a\0025\3\b\0=\3\t\2B\0\2\1K\0\1\0\14highlight\1\0\1\venable\2\vindent\1\0\1\venable\2\21ensure_installed\1\0\3\vindent\0\14highlight\0\21ensure_installed\0\1\n\0\0\6c\bcpp\blua\vpython\ago\15javascript\15typescript\trust\thtml\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)
-- Config for: tokyonight.nvim
time([[Config for tokyonight.nvim]], true)
try_loadstring("\27LJ\2\nÙ\2\0\0\5\0\14\0\0196\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\5\0005\4\4\0=\4\6\0035\4\a\0=\4\b\0034\4\0\0=\4\t\0034\4\0\0=\4\n\3=\3\v\0025\3\f\0=\3\r\2B\0\2\1K\0\1\0\rsidebars\1\5\0\0\aqf\thelp\rterminal\vpacker\vstyles\14variables\14functions\rkeywords\1\0\1\vitalic\2\rcomments\1\0\6\rkeywords\0\rcomments\0\vfloats\tdark\rsidebars\tdark\14variables\0\14functions\0\1\0\1\vitalic\2\1\0\6\29hide_inactive_statusline\1\rsidebars\0\vstyles\0\20terminal_colors\2\16transparent\2\nstyle\nnight\nsetup\15tokyonight\frequire\0", "config", "tokyonight.nvim")
time([[Config for tokyonight.nvim]], false)
-- Config for: leetcode.nvim
time([[Config for leetcode.nvim]], true)
try_loadstring("\27LJ\2\nç\a\0\0\a\0&\00036\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\4\0=\3\5\0025\3\v\0006\4\6\0009\4\a\0049\4\b\4'\6\t\0B\4\2\2'\5\n\0&\4\5\4=\4\f\0036\4\6\0009\4\a\0049\4\b\4'\6\r\0B\4\2\2'\5\n\0&\4\5\4=\4\r\3=\3\14\0025\3\15\0=\3\16\0025\3\17\0=\3\r\0025\3\18\0=\3\19\0025\3\20\0005\4\21\0=\4\22\0035\4\23\0=\4\24\0035\4\25\0=\4\26\3=\3\27\0025\3\28\0=\3\29\0025\3\30\0=\3\31\0025\3!\0005\4 \0=\4\"\0035\4#\0=\4$\3=\3%\2B\0\2\1K\0\1\0\tkeys\fconfirm\1\2\0\0\t<CR>\vtoggle\1\0\6\17use_testcase\6U\17focus_result\6L\20reset_testcases\6r\fconfirm\0\vtoggle\0\20focus_testcases\6H\1\2\0\0\6q\vpicker\1\0\1\rprovider\14telescope\16description\1\0\3\nwidth\b40%\15show_stats\2\rposition\tleft\fconsole\rtestcase\1\0\2\14virt_text\2\tsize\b40%\vresult\1\0\1\tsize\b60%\tsize\1\0\2\nwidth\b90%\vheight\b75%\1\0\5\20open_on_runcode\2\tsize\0\rtestcase\0\vresult\0\bdir\brow\veditor\1\0\2\17fold_imports\2\24reset_previous_code\2\1\0\1\20update_interval\3Äı$\fplugins\1\0\1\19non_standalone\1\fstorage\ncache\thome\1\0\2\ncache\0\thome\0\14/leetcode\tdata\fstdpath\afn\bvim\acn\1\0\3\23translate_problems\2\15translator\2\fenabled\1\1\0\r\acn\0\fconsole\0\barg\18leetcode.nvim\18image_support\1\veditor\0\vpicker\0\flogging\2\16description\0\fplugins\0\ncache\0\tlang\bcpp\fstorage\0\tkeys\0\nsetup\rleetcode\frequire\0", "config", "leetcode.nvim")
time([[Config for leetcode.nvim]], false)
-- Config for: bytelocker
time([[Config for bytelocker]], true)
try_loadstring("\27LJ\2\nY\0\0\3\0\4\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0B\0\2\1K\0\1\0\1\0\2\18setup_keymaps\2\vcipher\bxor\nsetup\15bytelocker\frequire\0", "config", "bytelocker")
time([[Config for bytelocker]], false)

_G._packer.inside_compile = false
if _G._packer.needs_bufread == true then
  vim.cmd("doautocmd BufRead")
end
_G._packer.needs_bufread = false

if should_profile then save_profiles() end

end)

if not no_errors then
  error_msg = error_msg:gsub('"', '\\"')
  vim.api.nvim_command('echohl ErrorMsg | echom "Error in packer_compiled: '..error_msg..'" | echom "Please check your config for correctness" | echohl None')
end
