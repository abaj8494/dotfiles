#!/bin/bash

# Script to refresh leetcode.nvim cookie
# Usage: Run this when you get cookie expiration errors

echo "🍪 LeetCode Cookie Refresh Helper"
echo "=================================="
echo ""
echo "1. Open LeetCode in your browser and log in"
echo "2. Press F12 → Application/Storage → Cookies → leetcode.com"
echo "3. Copy the LEETCODE_SESSION value"
echo "4. Run ':Leet cookie update' in Neovim and paste the value"
echo ""
echo "Current cookie file location:"
echo "~/.cache/nvim/leetcode/cookie"
echo ""
echo "To check current cookie expiry, run:"
echo "cat ~/.cache/nvim/leetcode/cookie | grep -o 'LEETCODE_SESSION=[^;]*'"
