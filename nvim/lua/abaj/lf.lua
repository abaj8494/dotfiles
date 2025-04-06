-- Custom lf module that avoids the problematic wrapper

local M = {}

-- Direct lf launcher that doesn't use the wrapper
M.open_direct = function()
  local height = vim.g.floaterm_height or 0.95
  local width = vim.g.floaterm_width or 0.95
  
  -- Get current path or working directory
  local current_path
  if vim.fn.expand('%:p:h') ~= '' then
    current_path = vim.fn.expand('%:p:h')
  else
    current_path = vim.fn.getcwd()
  end
  
  -- Directly launch floaterm with lf
  local cmd = string.format(
    'FloatermNew --height=%s --width=%s --title=lf lf %s',
    height,
    width,
    vim.fn.shellescape(current_path)
  )
  
  vim.cmd(cmd)
end

return M 