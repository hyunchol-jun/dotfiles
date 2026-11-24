-- Personal Hyprland settings for Omarchy, tracked in ~/dotfiles.
-- Linked to ~/.config/hypr/personal.lua by Dotbot and loaded by the
-- require("hypr.personal") line that scripts/hypr-setup.sh adds to
-- ~/.config/hypr/hyprland.lua. Omarchy's own files there stay stock, so its
-- updates never conflict with this one. Apply edits with: hyprctl reload

-- Input ----------------------------------------------------------------------

-- Natural scrolling on the trackpad, matching macOS.
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
    },
  },
})

-- Display scale ---------------------------------------------------------------
--
-- Omarchy's "auto" picks 1.5 for the ThinkPad's 14" 1920x1080 panel, which
-- leaves a 1280x720 desktop. 1.2 gives 1600x900. Hyprland only takes scales
-- that divide the resolution evenly: 1 (1920x1080), 1.2, 1.25 (1536x864), 1.5.
-- Named by output, so external monitors keep "auto".
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.2 })

-- No gaps ---------------------------------------------------------------------
--
-- Windows meet each other and the screen edges; a one-pixel border is left to
-- mark the focused one. (The wallpaper is plain black: see scripts/hypr-setup.sh.)
hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
  },
})

-- No animations ---------------------------------------------------------------
--
-- Windows, workspaces and layers change instantly.
hl.config({
  animations = {
    enabled = false,
  },
})

-- Always tile ------------------------------------------------------------------
--
-- Omarchy's Super+L cycles a workspace through tiling, scrolling and floating
-- (the floating one brings up a dock). Easy to hit by accident, so both
-- directions are unbound. If a workspace does end up in another layout, run
-- omarchy-hyprland-workspace-layout-toggle until it reports dwindle.
hl.unbind("SUPER + L")
hl.unbind("SUPER + ALT + L")

-- Ctrl+h/j/k/l moves focus between windows ------------------------------------
--
-- One set of keys walks through Neovim splits, tmux panes and app windows:
--   * A terminal running tmux or Neovim keeps the keys: the binds below are
--     switched off while it is focused. At their outer edge tmux and Neovim
--     call ~/dotfiles/bin/nav, which asks Hyprland to focus the next window
--     (see tmux/hypr-nav.conf and config/nvim/lua/custom/plugins/tmux-navigator.lua).
--   * Everywhere else, a terminal at a plain shell included, Hyprland takes
--     the keys itself. Apps lose their own Ctrl+H/J/K/L (in Chromium: history,
--     downloads, link search, address bar; in a shell: backspace, newline,
--     kill-line, clear), as shells inside tmux already do.

local terminal_classes = {
  "^Alacritty$",
  "^kitty$",
  "^com%.mitchellh%.ghostty$",
  "^foot$",
  "^org%.codeberg%.dnkl%.foot$",
  "^wezterm$",
  "^org%.omarchy%.",
  "^TUI%.",
}

local function is_terminal(window)
  -- Omarchy tags terminals in default/hypr/apps/terminals.lua.
  local tags = window.tags
  if type(tags) == "table" then
    for _, tag in ipairs(tags) do
      if tostring(tag):gsub("%*$", "") == "terminal" then
        return true
      end
    end
  end

  -- The tag is set by a window rule, which may not have run yet for a window
  -- that is only just opening, so fall back on the class.
  local class = window.class or ""
  for _, pattern in ipairs(terminal_classes) do
    if class:find(pattern) then
      return true
    end
  end

  return false
end

-- Programs that use Ctrl+h/j/k/l themselves. ssh and mosh count because the
-- far end is usually tmux; nothing hands focus back out of those.
local key_users = { "^tmux: client$", "^n?vim$", "^view$", "^fzf$", "^ssh$", "^mosh%-client$" }

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a") or ""
  file:close()
  return content
end

-- Whether the process or anything it started is one of key_users. Walks
-- /proc, which costs a few small reads and no process spawn.
local function runs_key_user(pid, depth)
  depth = depth or 0
  if depth > 8 then
    return false
  end

  local name = read_file("/proc/" .. pid .. "/comm"):gsub("%s+$", "")
  for _, pattern in ipairs(key_users) do
    if name:find(pattern) then
      return true
    end
  end

  for child in read_file("/proc/" .. pid .. "/task/" .. pid .. "/children"):gmatch("%d+") do
    if runs_key_user(child, depth + 1) then
      return true
    end
  end

  return false
end

local function window_keeps_keys(window)
  return window ~= nil and window.pid ~= nil and is_terminal(window) and runs_key_user(window.pid)
end

local focus_keys = {
  { key = "H", direction = "l", name = "left" },
  { key = "J", direction = "d", name = "below" },
  { key = "K", direction = "u", name = "above" },
  { key = "L", direction = "r", name = "right" },
}

local focus_binds = {}

local function sync_focus_binds()
  local enabled = not window_keeps_keys(hl.get_active_window())
  for _, bind in ipairs(focus_binds) do
    bind:set_enabled(enabled)
  end
  return enabled
end

for _, entry in ipairs(focus_keys) do
  focus_binds[#focus_binds + 1] = hl.bind("CTRL + " .. entry.key, function()
    -- tmux or Neovim may have started since the last check; from the next
    -- press on the keys are theirs.
    if sync_focus_binds() then
      hl.dispatch(hl.dsp.focus({ direction = entry.direction }))
    end
  end, { description = "Focus on " .. entry.name .. " window" })
end

-- The Lua state outlives a config reload, so stop the previous load's timers.
for _, name in ipairs({ "focus_poll", "power_poll" }) do
  if o.personal and o.personal[name] then
    pcall(function()
      o.personal[name]:set_enabled(false)
    end)
  end
end

-- Reachable from `hyprctl eval` for checking and debugging.
o.personal = { focus_binds = focus_binds, window_keeps_keys = window_keeps_keys }

hl.on("window.active", sync_focus_binds)
hl.on("window.title", sync_focus_binds)
-- Starting or leaving tmux in the focused terminal raises no event.
o.personal.focus_poll = hl.timer(sync_focus_binds, { timeout = 2000, type = "repeat" })
sync_focus_binds()

-- Super+W / Super+T act on browser tabs, as Cmd+W / Cmd+T do on macOS ----------
--
-- In a browser Super+W closes the tab and Super+T opens one: the browser is
-- sent its own Ctrl+W / Ctrl+T. Everywhere else the keys keep Omarchy's
-- meaning (close the window; toggle floating). Super+Q still closes the whole
-- window, browser included. To carry another Cmd shortcut over, add a line to
-- browser_keys.

-- Web apps (class chrome-<url>-Default) are single-page windows, not browsers.
local browser_classes = {
  "^google%-chrome",
  "^chromium",
  "^brave%-browser",
  "^firefox",
  "^zen",
}

local function is_browser(window)
  local class = window and window.class or ""
  for _, pattern in ipairs(browser_classes) do
    if class:find(pattern) then
      return true
    end
  end
  return false
end

-- Sent with explicit modifiers, so the Super still held down is not part of
-- the chord the app sees. Down and up are split as in Omarchy's
-- default/hypr/bindings/clipboard.lua, which found send_shortcut can leave
-- the key repeating.
local function send_keys(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local browser_keys = {
  { key = "W", description = "Close tab (browser) or window", otherwise = hl.dsp.window.close() },
  { key = "T", description = "New tab (browser) or toggle floating", otherwise = hl.dsp.window.float({ action = "toggle" }) },
}

for _, entry in ipairs(browser_keys) do
  o.rebind("SUPER + " .. entry.key, entry.description, function()
    if is_browser(hl.get_active_window()) then
      send_keys("CTRL", entry.key)
    else
      hl.dispatch(entry.otherwise)
    end
  end)
end

-- Ctrl+1..0 switches workspace, as on macOS ------------------------------------
--
-- Added next to Omarchy's Super+1..0, which keep working. Apps no longer see
-- Ctrl+digit (in Chromium: jump to tab N; Alt+digit does the same there).
for workspace = 1, 10 do
  -- Key codes 10-19 are the number row, whatever the keyboard layout.
  o.bind("CTRL + code:" .. tostring(workspace + 9), "Switch to workspace " .. workspace, o.workspaces.focus(workspace))
end

-- Plugged in: never idle --------------------------------------------------------
--
-- Omarchy starts a screensaver after 2.5 idle minutes and locks (display off)
-- after 5, on battery and on mains alike. On mains this switches its "stay
-- awake" state on, which stops both; on battery it switches it back off. The
-- power profile saved for that source is applied at the same time.
-- Super+Ctrl+I still toggles staying awake by hand until the next change.

local function on_mains()
  for _, name in ipairs({ "AC", "AC0", "ACAD", "ADP0", "ADP1" }) do
    local online = read_file("/sys/class/power_supply/" .. name .. "/online")
    if online ~= "" then
      return online:find("1", 1, true) ~= nil
    end
  end
  return false -- No adapter to read (a desktop): leave idling as it is.
end

local last_mains = nil

local function sync_power()
  local mains = on_mains()
  if mains == last_mains then
    return
  end
  last_mains = mains

  hl.exec_cmd("omarchy-toggle-idle " .. (mains and "stay-awake" or "allow-idle"))
  hl.exec_cmd("omarchy-powerprofiles-set autodetect")
end

o.personal.power_poll = hl.timer(sync_power, { timeout = 5000, type = "repeat" })
sync_power()

-- Window placement, after the Raycast shortcuts on the Mac --------------------
--
--   Alt+H/J/K/L        left / bottom / top / right half
--   Alt+M              maximize
--   Alt+C              centered at half the screen width
--   Shift+Alt+←/→      move the window to the monitor on that side
--
-- Hyprland tiles, so a "half" depends on what else is on the workspace:
--   * A window tiled next to others moves that way inside the tiling, which
--     with two windows puts it on that half.
--   * A window alone on its workspace (or already floating) has no tiling to
--     move in, so it floats and snaps to that half, as on the Mac. The same
--     happens when the tiling cannot give that half (three or more windows).
-- Alt+M puts a floating window back into the tiling and makes it fill the
-- workspace; pressed again on a tiled window it toggles the maximize off.

local function target(window)
  return "address:" .. window.address
end

-- The part of the window's monitor that a tiled window may cover, in the
-- layout's coordinates: inside the bar, the outer gaps and the border.
local function usable_area(window)
  local monitor = window.monitor or hl.get_active_monitor()
  local scale = monitor.scale or 1
  local reserved = type(monitor.reserved) == "table" and monitor.reserved or {}
  local gaps = hl.get_config("general.gaps_out")
  local border = tonumber(hl.get_config("general.border_size")) or 0

  local function inset(side)
    local gap = type(gaps) == "table" and gaps[side] or tonumber(gaps) or 0
    return (reserved[side] or 0) + gap + border
  end

  return {
    x = monitor.x + inset("left"),
    y = monitor.y + inset("top"),
    w = monitor.width / scale - inset("left") - inset("right"),
    h = monitor.height / scale - inset("top") - inset("bottom"),
  }
end

-- Space left between two halves, to match the gap between tiled windows.
local function seam()
  local gaps = hl.get_config("general.gaps_in")
  local gap = type(gaps) == "table" and gaps.left or tonumber(gaps) or 0
  local border = tonumber(hl.get_config("general.border_size")) or 0
  return 2 * (gap + border)
end

local function tiled_neighbours(window)
  local count = 0
  if window.workspace then
    for _, other in ipairs(hl.get_workspace_windows(tostring(window.workspace.id))) do
      if not other.floating and other.address ~= window.address then
        count = count + 1
      end
    end
  end
  return count
end

local function leave_fullscreen(window)
  if window.fullscreen and window.fullscreen ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = target(window) }))
  end
end

local function float_at(window, x, y, w, h)
  local address = target(window)
  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "on", window = address }))
  end
  hl.dispatch(hl.dsp.window.resize({ x = math.floor(w), y = math.floor(h), window = address }))
  hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = address }))
end

local place = {}

-- Whether the window already sits against that edge without spanning the area.
local function on_half(window, area, direction)
  local at, size = window.at, window.size
  local near = function(a, b)
    return math.abs(a - b) <= 2
  end

  if direction == "l" then
    return near(at.x, area.x) and size.x < area.w - 2
  elseif direction == "r" then
    return near(at.x + size.x, area.x + area.w) and size.x < area.w - 2
  elseif direction == "u" then
    return near(at.y, area.y) and size.y < area.h - 2
  else
    return near(at.y + size.y, area.y + area.h) and size.y < area.h - 2
  end
end

local function snap_half(window, area, direction)
  local half_w, half_h = (area.w - seam()) / 2, (area.h - seam()) / 2
  if direction == "l" then
    float_at(window, area.x, area.y, half_w, area.h)
  elseif direction == "r" then
    float_at(window, area.x + area.w - half_w, area.y, half_w, area.h)
  elseif direction == "u" then
    float_at(window, area.x, area.y, area.w, half_h)
  else
    float_at(window, area.x, area.y + area.h - half_h, area.w, half_h)
  end
end

function place.half(direction, window)
  window = window or hl.get_active_window()
  if not window then
    return
  end
  leave_fullscreen(window)

  local area = usable_area(window)
  local neighbours = tiled_neighbours(window)
  if window.floating or neighbours == 0 then
    snap_half(window, area, direction)
    return
  end

  -- Tiled next to others: rearrange the tiling. Window objects are live, so
  -- on_half sees the result of each step straight away.
  if on_half(window, area, direction) then
    return
  end

  hl.dispatch(hl.dsp.window.move({ direction = direction, window = target(window) }))
  if on_half(window, area, direction) then
    return
  end

  -- Two windows split the other way (side by side when asked for top/bottom,
  -- or stacked when asked for left/right): turn the split, then pick the side.
  local active = hl.get_active_window()
  local layout = window.workspace and window.workspace.tiled_layout
  if neighbours == 1 and layout == "dwindle" and active and active.address == window.address then
    hl.dispatch(hl.dsp.layout("togglesplit"))
    if not on_half(window, area, direction) then
      hl.dispatch(hl.dsp.window.move({ direction = direction, window = target(window) }))
    end
    if on_half(window, area, direction) then
      return
    end
  end

  -- No tiled arrangement gives that half (three or more windows, or another
  -- layout), so take it as a floating window.
  snap_half(window, area, direction)
end

function place.maximize(window)
  window = window or hl.get_active_window()
  if not window then
    return
  end

  local address = target(window)
  if window.floating then
    leave_fullscreen(window)
    hl.dispatch(hl.dsp.window.float({ action = "off", window = address }))
    if tiled_neighbours(window) > 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = address }))
    end
  else
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = address }))
  end
end

function place.center(window)
  window = window or hl.get_active_window()
  if not window then
    return
  end
  leave_fullscreen(window)

  local area = usable_area(window)
  float_at(window, area.x + area.w / 4, area.y, area.w / 2, area.h)
end

o.personal.place = place

local function placing(fn, argument)
  return function()
    fn(argument)
  end
end

o.bind("ALT + H", "Window to left half", placing(place.half, "l"))
o.bind("ALT + L", "Window to right half", placing(place.half, "r"))
o.bind("ALT + K", "Window to top half", placing(place.half, "u"))
o.bind("ALT + J", "Window to bottom half", placing(place.half, "d"))
o.bind("ALT + M", "Maximize window", placing(place.maximize))
o.bind("ALT + C", "Center window at half width", placing(place.center))
o.bind("SHIFT + ALT + LEFT", "Move window to left monitor", o.workspaces.move_window_to_monitor("l"))
o.bind("SHIFT + ALT + RIGHT", "Move window to right monitor", o.workspaces.move_window_to_monitor("r"))

-- Startup layout: terminal on workspace 1, browser on workspace 2 --------------
--
-- The launchers hand their app to systemd, so Hyprland cannot follow the
-- process to place its window. A window rule does the placing instead, and is
-- switched off once the first matching window has opened (or after a minute),
-- so windows opened later land on whatever workspace is in view.

-- `class` is a regex for the window rule; `patterns` are Lua patterns for the
-- same classes (Lua has no alternation), used to spot the window opening.
function o.personal.open_on_workspace(class, patterns, workspace, command)
  local rule = hl.window_rule({ match = { class = class }, workspace = workspace .. " silent" })

  local function matches(window_class)
    for _, pattern in ipairs(patterns) do
      if window_class:find(pattern) then
        return true
      end
    end
    return false
  end
  local pending = true

  local function done()
    if pending then
      pending = false
      rule:set_enabled(false)
    end
  end

  hl.on("window.open", function(window)
    if pending and window and matches(window.class or "") then
      -- Leave the rule on for a moment: it is applied as the window maps.
      hl.timer(done, { timeout = 2000, type = "oneshot" })
    end
  end)
  hl.timer(done, { timeout = 60000, type = "oneshot" })

  hl.exec_cmd(command)
end

-- Try it without a reboot: hyprctl eval 'o.personal.startup_layout()'
function o.personal.startup_layout()
  o.personal.open_on_workspace("org\\.omarchy\\.terminal", { "^org%.omarchy%.terminal$" }, 1, "omarchy-launch-terminal")
  -- Follows the default browser (scripts/chrome.sh makes that Chrome).
  o.personal.open_on_workspace("(chromium|google-chrome.*)", { "^chromium$", "^google%-chrome" }, 2, "omarchy-launch-browser")
end

hl.on("hyprland.start", o.personal.startup_layout)
