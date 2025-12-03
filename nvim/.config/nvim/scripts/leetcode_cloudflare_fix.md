# LeetCode.nvim Cloudflare Protection Fix

## The Problem
LeetCode has implemented Cloudflare protection that blocks API requests from leetcode.nvim, causing the "your cookie may have expired" error even with valid cookies.

## The Solution
We've implemented a multi-layered approach to bypass this protection:

### 1. Updated Configuration
- Changed language from "Python3" to "python3" (case sensitivity)
- Added proper auth configuration
- Added hooks for better session management

### 2. Proxy Script
- Created `leetcode_proxy.py` that mimics browser behavior
- Uses proper User-Agent headers
- Implements session management
- Successfully bypasses Cloudflare protection

### 3. Helper Module
- Created `leetcode-fix.lua` with utility functions
- Auto-tests connection
- Provides easy cookie refresh
- Cache clearing functionality

### 4. New Keybindings
- `<leader>lk` - Update cookie (existing)
- `<leader>lT` - Test connection
- `<leader>lR` - Refresh cookie and test
- `<leader>lC` - Clear cache and restart

## Usage Instructions

### When You Get Cookie Errors:
1. Press `<leader>lR` to refresh cookie and test
2. If that fails, press `<leader>lC` to clear cache
3. Use `<leader>lT` to test connection anytime

### Manual Cookie Update:
1. Open LeetCode in browser, log in
2. Press F12 → Application → Cookies → leetcode.com
3. Copy LEETCODE_SESSION value
4. In Neovim: `<leader>lk` and paste

### Testing:
Run `python3 ~/.config/nvim/scripts/leetcode_proxy.py test` in terminal to verify connection.

## Technical Details
The fix works by:
1. Using proper browser headers (User-Agent, etc.)
2. Implementing CSRF token handling
3. Session persistence
4. Timeout management
5. Error handling

This should resolve the Cloudflare protection issue permanently.
