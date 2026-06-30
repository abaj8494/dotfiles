-- Allow `osascript -e 'tell application "Hammerspoon" to execute lua code ...'`
-- so future config reloads can be triggered from the terminal.
hs.allowAppleScript(true)

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

-- ──────────────────────────────────────────────────────────────────────────
-- RPI4 screen sync
-- When the Mac display sleeps/wakes, mirror the state on the Pi 4's DSI
-- touchscreen. Local touch input still wakes the Pi independently.
-- ──────────────────────────────────────────────────────────────────────────

local RPI_HOST  = "rpi.local"
local RPI_KEY   = os.getenv("HOME") .. "/.ssh/id_ed25519"

local RPI_LOG = os.getenv("HOME") .. "/.hammerspoon/rpi-display.log"

local function rpiLog(line)
  local f = io.open(RPI_LOG, "a")
  if f then
    f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), line))
    f:close()
  end
end

local function rpiDisplay(state)
  rpiLog("dispatch " .. state)
  hs.task.new("/usr/bin/ssh",
    function(exitCode, _, stderr)
      rpiLog(string.format("ssh %s exit=%d %s", state, exitCode, (stderr or ""):gsub("\n", " | ")))
    end,
    { "-i", RPI_KEY,
      "-o", "ConnectTimeout=3",
      "-o", "BatchMode=yes",
      "-o", "StrictHostKeyChecking=accept-new",
      "root@" .. RPI_HOST,
      "/usr/local/bin/rpi-display " .. state }
  ):start()
end

local EVENT_NAMES = {
  [hs.caffeinate.watcher.screensDidSleep]   = "screensDidSleep",
  [hs.caffeinate.watcher.screensDidWake]    = "screensDidWake",
  [hs.caffeinate.watcher.systemWillSleep]   = "systemWillSleep",
  [hs.caffeinate.watcher.systemDidWake]     = "systemDidWake",
  [hs.caffeinate.watcher.systemWillPowerOff]= "systemWillPowerOff",
  [hs.caffeinate.watcher.screensaverDidStart]    = "screensaverDidStart",
  [hs.caffeinate.watcher.screensaverDidStop]     = "screensaverDidStop",
  [hs.caffeinate.watcher.screensaverWillStop]    = "screensaverWillStop",
  [hs.caffeinate.watcher.sessionDidBecomeActive] = "sessionDidBecomeActive",
  [hs.caffeinate.watcher.sessionDidResignActive] = "sessionDidResignActive",
  [hs.caffeinate.watcher.screensDidLock]            = "screensDidLock",
  [hs.caffeinate.watcher.screensDidUnlock]          = "screensDidUnlock",
}

-- Only mirror sleep/wake when at least one external monitor is connected to
-- the Mac. Laptop-alone scenarios shouldn't drag the bedroom kiosk along
-- with the lid-close / idle-sleep cycle.
local function hasExternalMonitors()
  return #hs.screen.allScreens() > 1
end

-- Treat both true display-sleep and lockscreen events as "off"; both wake/unlock as "on".
-- Lock events fire when the Mac engages the lockscreen without putting the panel to sleep
-- (e.g. screensaver-into-lock); they're the only signal we get for that path.
caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
  local e = hs.caffeinate.watcher
  local ext = hasExternalMonitors()
  rpiLog("event " .. (EVENT_NAMES[event] or tostring(event)) .. " external=" .. tostring(ext))
  if not ext then return end  -- laptop-only: leave the Pi alone
  if event == e.screensDidSleep
      or event == e.systemWillSleep
      or event == e.screensDidLock then
    rpiDisplay("off")
  elseif event == e.screensDidWake
      or event == e.systemDidWake
      or event == e.screensDidUnlock then
    rpiDisplay("on")
  end
end)
caffeinateWatcher:start()
rpiLog(string.format("watcher armed (external monitors at boot=%s)", tostring(hasExternalMonitors())))

-- screen.watcher: mirror external-monitor plug/unplug onto the Pi. The
-- caffeinate watcher only fires on sleep/wake/lock; plugging or unplugging the
-- external display while the Mac stays awake doesn't trip any of those.
--   * unplug (had external, now laptop-only) → off, so the Pi doesn't stay lit
--     after the Mac goes laptop-only.
--   * re-plug (was laptop-only, now external present) → on, the symmetric wake.
--     Re-plugging doesn't emit a screensDidWake/Unlock, so without this the Pi
--     would sit dark until the next lock/unlock cycle.
local prevHadExternal = hasExternalMonitors()
screenWatcher = hs.screen.watcher.new(function()
  local hasExt = hasExternalMonitors()
  rpiLog(string.format("screen change: had=%s now=%s", tostring(prevHadExternal), tostring(hasExt)))
  if prevHadExternal and not hasExt then
    rpiLog("external monitor unplugged → rpi off")
    rpiDisplay("off")
  elseif not prevHadExternal and hasExt then
    rpiLog("external monitor re-plugged → rpi on")
    rpiDisplay("on")
  end
  prevHadExternal = hasExt
end)
screenWatcher:start()
rpiLog("screen.watcher armed")

-- Startup reconciliation: when Hammerspoon loads (Mac boot, kernel-panic
-- recovery, or `hs.reload()`), the Pi may have been left in any state from
-- the previous session. If external monitors are connected (the same gate
-- the caffeinate watcher uses), explicitly send "on" so the Pi screen is
-- in a known-good state matching the Mac being currently awake.
--
-- Delayed by ~6 s because immediately after Mac boot the Wi-Fi stack often
-- isn't routable yet; an early SSH would 100% fail with "no route to host"
-- and we'd lose the only reconciliation chance. 6 s is long enough for
-- DHCP + mDNS to settle, short enough that the Pi wake feels concurrent
-- with the user's first sight of the Mac.
rpiLog("startup reconciliation: scheduling wake in 6s")
rpiStartupTimer = hs.timer.doAfter(6, function()
  rpiLog("startup reconciliation: timer fired")
  if hasExternalMonitors() then
    rpiDisplay("on")
  else
    rpiLog("startup reconciliation: no external monitors, skipping wake")
  end
end)

-- ──────────────────────────────────────────────────────────────────────────
-- Window layout snapshots (Aerospace-aware)
-- Records each window's Aerospace workspace every 30 min. On the first
-- Hammerspoon load of a new boot session, waits ~15s for apps to relaunch
-- and replays `aerospace move-node-to-workspace` so windows land back on
-- the workspaces they were on before reboot. A boot-marker file ensures
-- subsequent `hs.reload`s in the same session don't retile.
-- ──────────────────────────────────────────────────────────────────────────

local AEROSPACE      = "/opt/homebrew/bin/aerospace"
local SYSCTL         = "/usr/sbin/sysctl"
local LAYOUT_DIR     = os.getenv("HOME") .. "/.hammerspoon/window-layouts"
local LAYOUT_LATEST  = LAYOUT_DIR .. "/latest.json"
local LAYOUT_LOG     = os.getenv("HOME") .. "/.hammerspoon/window-layouts.log"
local BOOT_MARKER    = LAYOUT_DIR .. "/.last-restore-boot"
local LAYOUT_HISTORY = 24  -- 12h of history at a 30-min cadence
local LIST_FORMAT    = "%{window-id}|%{workspace}|%{app-bundle-id}|%{app-name}|%{window-title}"

hs.fs.mkdir(LAYOUT_DIR)

local function layoutLog(line)
  local f = io.open(LAYOUT_LOG, "a")
  if f then
    f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), line))
    f:close()
  end
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function writeFile(path, body)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(body); f:close()
  return true
end

local function parseAerospaceList(stdout)
  local out = {}
  for line in (stdout or ""):gmatch("([^\n]+)") do
    local id, ws, bundle, app, title = line:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if id then
      table.insert(out, { id = id, workspace = ws, bundle = bundle, app = app, title = title })
    end
  end
  return out
end

local function pruneLayoutHistory()
  local files = {}
  local ok = pcall(function()
    for f in hs.fs.dir(LAYOUT_DIR) do
      if f:match("^snapshot%-.+%.json$") then table.insert(files, f) end
    end
  end)
  if not ok then return end
  table.sort(files)
  while #files > LAYOUT_HISTORY do
    os.remove(LAYOUT_DIR .. "/" .. table.remove(files, 1))
  end
end

-- opts.historyOnly: write the timestamped snapshot but never touch
-- latest.json. Used by the post-restore save so a partial/half-converged
-- restore can't overwrite the good pre-crash baseline that latest.json holds.
local function saveLayout(reason, opts)
  opts = opts or {}
  hs.task.new(AEROSPACE, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      layoutLog(string.format("save reason=%s aerospace-failed exit=%d %s",
        reason or "?", exitCode, (stderr or ""):gsub("\n", " | ")))
      return
    end
    local live = parseAerospaceList(stdout)
    local snap = {}
    for _, w in ipairs(live) do
      -- window-id is volatile across reboots; re-resolved at restore time.
      table.insert(snap, {
        workspace = w.workspace,
        bundle    = w.bundle,
        app       = w.app,
        title     = w.title,
      })
    end
    local body  = hs.json.encode(snap, true)
    local stamp = os.date("%Y%m%d-%H%M%S")
    writeFile(string.format("%s/snapshot-%s.json", LAYOUT_DIR, stamp), body)
    if opts.historyOnly then
      layoutLog(string.format("save reason=%s windows=%d history-only", reason or "timer", #snap))
    elseif #snap > 0 then
      -- Refuse to overwrite latest.json with an empty capture: sleep/lock
      -- transients can return 0 windows, and we don't want to nuke the only
      -- good pre-reboot snapshot.
      writeFile(LAYOUT_LATEST, body)
      layoutLog(string.format("save reason=%s windows=%d", reason or "timer", #snap))
    else
      layoutLog(string.format("save reason=%s windows=0 latest-not-updated", reason or "timer"))
    end
    pruneLayoutHistory()
  end, { "list-windows", "--all", "--format", LIST_FORMAT }):start()
end

-- ── App launching ─────────────────────────────────────────────────────────
-- A crash leaves apps un-relaunched, so the restorer has to *start* them, not
-- just move existing windows. Default launcher is `open -b <bundle>`; override
-- per-bundle below for apps that need a special incantation.
local OPEN         = "/usr/bin/open"
local EMACS_CLIENT = "/Applications/MacPorts/Emacs.app/Contents/MacOS/bin/emacsclient"

-- Emacs is a launchd `runatload` daemon: it auto-starts on boot and holds all
-- buffer state. We must NOT `open -b org.gnu.Emacs` (spawns a second, non-daemon
-- Emacs) and must NOT kickstart -k the daemon (kills live state). Just ask the
-- running daemon for a GUI frame — the same final step as the `er` shell alias,
-- minus the destructive restart. Each call makes one frame, so multi-frame
-- layouts converge over successive ticks. If the daemon isn't up yet this
-- no-ops and the next tick retries.
local LAUNCHERS = {
  ["org.gnu.Emacs"] = function(cb)
    hs.task.new(EMACS_CLIENT, function(code, _, err) cb(code, err) end,
      { "-c", "-n" }):start()
  end,
}

-- Bundles to never auto-launch during restore (leave these windows dead).
local NO_LAUNCH = {}

local function launchApp(bundle, cb)
  local fn = LAUNCHERS[bundle]
  if fn then return fn(cb) end
  hs.task.new(OPEN, function(code, _, err) cb(code, err) end, { "-b", bundle }):start()
end

-- Convergence-based restore. A single pass can't work after a crash: heavy
-- apps (JVM/Ghidra, Docker) take far longer than any fixed delay to relaunch,
-- and apps macOS didn't bring back aren't running at all. So we reconcile on a
-- short loop — match live windows to the saved layout, move mismatches, and
-- launch any bundle that still has no window — until everything is placed or
-- the time budget runs out.
local CONVERGE_TICK     = 2     -- seconds between reconciliation passes
local CONVERGE_BUDGET   = 120   -- total seconds to wait for apps to appear
local LAUNCH_COOLDOWN   = 5      -- per-bundle min seconds between launch attempts
local LAUNCH_MAX_TRIES  = 3      -- give up launching a bundle after this many tries

local restoreInFlight = false
local reconTimer = nil

local function restoreLayout(opts)
  opts = opts or {}
  local body = readFile(LAYOUT_LATEST)
  if not body then
    layoutLog("restore: no snapshot")
    if not opts.quiet then
      hs.notify.new({ title = "Window layout", informativeText = "no snapshot to restore" }):send()
    end
    if opts.onDone then opts.onDone(false) end
    return
  end
  local snap = hs.json.decode(body)
  if not snap or #snap == 0 then
    layoutLog("restore: snapshot empty")
    if opts.onDone then opts.onDone(false) end
    return
  end
  if restoreInFlight then
    layoutLog("restore: already in flight, ignoring")
    if opts.onDone then opts.onDone(false) end
    return
  end

  -- Build the desired set, dropping legacy frame-only entries (pre-Aerospace
  -- snapshots with no workspace field — nothing actionable).
  local desired, legacy = {}, 0
  for _, e in ipairs(snap) do
    if e.workspace and e.workspace ~= "" then
      table.insert(desired, { workspace = e.workspace, bundle = e.bundle,
                              title = e.title or "", done = false })
    else
      legacy = legacy + 1
    end
  end
  if #desired == 0 then
    layoutLog(string.format("restore: nothing actionable (legacy=%d)", legacy))
    if opts.onDone then opts.onDone(false) end
    return
  end

  restoreInFlight = true
  local deadline    = os.time() + CONVERGE_BUDGET
  local lastLaunch  = {}   -- bundle -> os.time() of last launch attempt
  local launchTries = {}   -- bundle -> attempts so far
  local moved, launched = 0, 0

  local function remainingCount()
    local n = 0
    for _, e in ipairs(desired) do if not e.done then n = n + 1 end end
    return n
  end

  local function finish(reason)
    restoreInFlight = false
    local remaining = remainingCount()
    layoutLog(string.format("restore %s: moved=%d launched=%d placed=%d/%d unresolved=%d legacy=%d",
      reason, moved, launched, #desired - remaining, #desired, remaining, legacy))
    if not opts.quiet then
      hs.notify.new({
        title = "Window layout restored",
        informativeText = string.format("%d placed, %d launched, %d unresolved",
          #desired - remaining, launched, remaining),
      }):send()
    end
    if opts.onDone then opts.onDone(true) end
  end

  -- One reconciliation pass.
  local tick
  tick = function()
    hs.task.new(AEROSPACE, function(exitCode, stdout, stderr)
      if exitCode ~= 0 then
        layoutLog(string.format("restore tick: aerospace list failed exit=%d %s",
          exitCode, (stderr or ""):gsub("\n", " | ")))
        if os.time() >= deadline then return finish("timeout") end
        reconTimer = hs.timer.doAfter(CONVERGE_TICK, tick)
        return
      end

      local live = parseAerospaceList(stdout)
      -- group live windows by bundle; matches consume from the pool so
      -- multi-window apps map 1:1 across the saved set.
      local byBundle = {}
      for _, w in ipairs(live) do
        byBundle[w.bundle] = byBundle[w.bundle] or {}
        table.insert(byBundle[w.bundle], w)
      end

      local moves    = {}
      local needLaunch = {}   -- bundle present as a key when a window is still missing
      for _, e in ipairs(desired) do
        if not e.done then
          local pool = byBundle[e.bundle]
          local matched
          if pool and #pool > 0 then
            if e.title ~= "" then
              for i, w in ipairs(pool) do
                if w.title == e.title then matched = table.remove(pool, i); break end
              end
            end
            matched = matched or table.remove(pool, 1)  -- positional fallback
          end
          if matched then
            if matched.workspace == e.workspace then
              e.done = true
            else
              table.insert(moves, { entry = e, id = matched.id })
            end
          else
            needLaunch[e.bundle] = true
          end
        end
      end

      -- Launch bundles that still lack a window (throttled + capped per bundle).
      local now = os.time()
      for bundle in pairs(needLaunch) do
        local tries = launchTries[bundle] or 0
        local cooled = not lastLaunch[bundle] or (now - lastLaunch[bundle]) >= LAUNCH_COOLDOWN
        if not NO_LAUNCH[bundle] and tries < LAUNCH_MAX_TRIES and cooled then
          lastLaunch[bundle]  = now
          launchTries[bundle] = tries + 1
          launched = launched + 1
          layoutLog(string.format("restore: launching %s (try %d)", bundle, tries + 1))
          launchApp(bundle, function(code, err)
            if code ~= 0 then
              layoutLog(string.format("restore: launch %s failed exit=%s %s",
                bundle, tostring(code), (err or ""):gsub("\n", " | ")))
            end
          end)
        end
      end

      -- Run moves sequentially — concurrent move-node-to-workspace calls can
      -- race aerospace's internal model — then decide whether to tick again.
      local mi = 1
      local function runMove()
        if mi > #moves then
          if remainingCount() == 0 then return finish("converged") end
          if os.time() >= deadline then return finish("timeout") end
          reconTimer = hs.timer.doAfter(CONVERGE_TICK, tick)
          return
        end
        local m = moves[mi]; mi = mi + 1
        hs.task.new(AEROSPACE, function(code, _, errOut)
          if code == 0 then
            moved = moved + 1
            m.entry.done = true
          else
            layoutLog(string.format("restore move %s→%s failed: %s",
              m.entry.bundle or "?", m.entry.workspace, (errOut or ""):gsub("\n", " | ")))
          end
          runMove()
        end, { "move-node-to-workspace", "--window-id", m.id, m.entry.workspace }):start()
      end
      runMove()
    end, { "list-windows", "--all", "--format", LIST_FORMAT }):start()
  end

  layoutLog(string.format("restore start: desired=%d legacy=%d budget=%ds",
    #desired, legacy, CONVERGE_BUDGET))
  tick()
end

-- Boot detection: kern.boottime's sec field changes on every reboot. We
-- record it in BOOT_MARKER the first time we auto-restore; subsequent
-- Hammerspoon reloads in the same session see the value match and skip.
local function currentBootSec()
  local f = io.popen(SYSCTL .. " -n kern.boottime 2>/dev/null")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s:match("sec = (%d+)")
end

local function alreadyRestoredThisBoot()
  local bootSec = currentBootSec()
  if not bootSec then return false, nil end
  local recorded = readFile(BOOT_MARKER)
  if recorded and recorded:gsub("%s+", "") == bootSec then
    return true, bootSec
  end
  return false, bootSec
end

windowLayoutTimer = hs.timer.doEvery(30 * 60, function() saveLayout("timer") end)

local restoredAlready, bootSec = alreadyRestoredThisBoot()
if restoredAlready then
  layoutLog("startup: already restored this boot (boot=" .. (bootSec or "?") .. "); skipping")
else
  layoutLog("startup: scheduling auto-restore in 15s (boot=" .. (bootSec or "?") .. ")")
  windowLayoutRestoreTimer = hs.timer.doAfter(15, function()
    layoutLog("startup: auto-restore firing")
    restoreLayout({ onDone = function(_)
      -- Mark this boot as handled regardless of success, so hs.reload()s
      -- don't retrigger. Manual hotkey (cmd+ctrl+alt+R) is the escape hatch.
      if bootSec then writeFile(BOOT_MARKER, bootSec) end
      -- History-only: a partial restore (apps that never relaunched) must not
      -- overwrite latest.json — that's the pre-crash baseline restore reads.
      -- The 30-min timer refreshes latest.json once you're back in steady state.
      saveLayout("post-restore", { historyOnly = true })
    end })
  end)
end

hs.hotkey.bind({ "cmd", "ctrl", "alt" }, "S", function() saveLayout("manual") end)
hs.hotkey.bind({ "cmd", "ctrl", "alt" }, "R", function() restoreLayout() end)

layoutLog("window layout watcher armed")
