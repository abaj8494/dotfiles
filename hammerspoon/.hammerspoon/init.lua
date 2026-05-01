-- ZSA Moonlander auto-switch
-- When the Moonlander connects/disconnects (typically via the dock), flip:
--   aerospace preset (dvorak <-> qwerty)
--   karabiner profile (bajaj <-> debug)
--   macOS keyboard layout (dvorak-nude <-> Australian)
-- All three swaps live in ~/dotfiles/scripts/keyboard-switch.sh.

local MOONLANDER_VENDOR  = 12951  -- 0x3297, ZSA Technology Labs
local MOONLANDER_PRODUCT = 6505   -- 0x1969, Moonlander Mark I
local SWITCH_SCRIPT      = os.getenv("HOME") .. "/dotfiles/scripts/keyboard-switch.sh"

local function runSwitch(mode)
  hs.task.new(SWITCH_SCRIPT, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      hs.notify.new({
        title = "keyboard-switch failed (" .. mode .. ")",
        informativeText = "exit " .. tostring(exitCode) .. ": " .. (stderr or ""),
      }):send()
    end
    print(string.format("[keyboard-switch] mode=%s exit=%d %s", mode, exitCode, stdout or ""))
  end, { mode }):start()
end

local function moonlanderAttached()
  for _, dev in ipairs(hs.usb.attachedDevices() or {}) do
    if dev.vendorID == MOONLANDER_VENDOR and dev.productID == MOONLANDER_PRODUCT then
      return true
    end
  end
  return false
end

usbWatcher = hs.usb.watcher.new(function(event)
  if event.vendorID == MOONLANDER_VENDOR and event.productID == MOONLANDER_PRODUCT then
    runSwitch(event.eventType == "added" and "moonlander" or "laptop")
  end
end)
usbWatcher:start()

-- Sync state on Hammerspoon load (and on every config reload). Idempotent — running
-- `keyboardSwitcher select <current>` and `aerospace reload-config` are no-ops in steady state.
runSwitch(moonlanderAttached() and "moonlander" or "laptop")

hs.notify.new({ title = "Hammerspoon", informativeText = "Moonlander watcher armed" }):send()
