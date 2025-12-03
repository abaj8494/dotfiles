-- LeetCode.nvim Cloudflare bypass fix
-- This module provides workarounds for the cookie expiration issue

local M = {}

-- Path to the proxy script
local proxy_script = vim.fn.stdpath("config") .. "/scripts/leetcode_proxy.py"

-- Function to test connection
function M.test_connection()
    local result = vim.fn.system("python3 " .. proxy_script .. " test")
    if vim.v.shell_error == 0 then
        print("✅ LeetCode connection successful!")
        return true
    else
        print("❌ LeetCode connection failed: " .. result)
        return false
    end
end

-- Function to refresh cookie and test
function M.refresh_and_test()
    vim.cmd("Leet cookie update")
    vim.defer_fn(function()
        M.test_connection()
    end, 1000) -- Wait 1 second for cookie to be saved
end

-- Function to clear cache and restart
function M.clear_cache_and_restart()
    local cache_dir = vim.fn.stdpath("cache") .. "/leetcode"
    vim.fn.system("rm -rf " .. cache_dir .. "/*")
    print("🗑️  Cleared LeetCode cache")
    vim.cmd("Leet")
end

-- Auto-test connection when entering a leetcode buffer
function M.setup_auto_test()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "leetcode",
        callback = function()
            -- Test connection when opening a leetcode file
            vim.defer_fn(function()
                M.test_connection()
            end, 2000) -- Wait 2 seconds after opening
        end,
    })
end

-- Setup keymaps
function M.setup_keymaps()
    vim.keymap.set('n', '<leader>lT', M.test_connection, { desc = 'Test LeetCode connection' })
    vim.keymap.set('n', '<leader>lR', M.refresh_and_test, { desc = 'Refresh cookie and test' })
    vim.keymap.set('n', '<leader>lC', M.clear_cache_and_restart, { desc = 'Clear cache and restart' })
end

-- Main setup function
function M.setup()
    M.setup_keymaps()
    M.setup_auto_test()
    
    -- Print helpful message
    print("🔧 LeetCode fix loaded. Use <leader>lT to test connection, <leader>lR to refresh cookie")
end

return M
