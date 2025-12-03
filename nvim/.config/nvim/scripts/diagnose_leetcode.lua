-- LeetCode diagnostic script
-- Run this in Neovim with :luafile ~/.config/nvim/scripts/diagnose_leetcode.lua

local function test_problem(problem_id)
    print("Testing problem " .. problem_id .. "...")
    
    -- Try to open the problem
    local success, err = pcall(function()
        vim.cmd("Leet " .. problem_id)
    end)
    
    if success then
        print("✅ Problem " .. problem_id .. " opened successfully")
        
        -- Wait a bit then try to test
        vim.defer_fn(function()
            local test_success, test_err = pcall(function()
                vim.cmd("Leet test")
            end)
            
            if test_success then
                print("✅ Problem " .. problem_id .. " test command executed")
            else
                print("❌ Problem " .. problem_id .. " test failed: " .. tostring(test_err))
            end
        end, 2000)
    else
        print("❌ Problem " .. problem_id .. " failed to open: " .. tostring(err))
    end
end

-- Test sequence
print("🔍 Starting LeetCode diagnostic...")
print("Current working directory: " .. vim.fn.getcwd())
print("LeetCode data dir: " .. vim.fn.stdpath("data") .. "/leetcode")
print("LeetCode cache dir: " .. vim.fn.stdpath("cache") .. "/leetcode")
print("")

-- Test different problems
local problems_to_test = {"1", "2", "260", "338"}

for i, problem in ipairs(problems_to_test) do
    vim.defer_fn(function()
        test_problem(problem)
    end, i * 5000) -- 5 second delay between tests
end

