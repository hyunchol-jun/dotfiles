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

-- Ctrl+h/j/k/l moves focus between windows ------------------------------------
--
-- One set of keys walks through Neovim splits, tmux panes and app windows:
--   * In a terminal the binds below are switched off, so the keys reach tmux
--     and Neovim untouched. At their outer edge those call ~/dotfiles/bin/nav,
--     which asks Hyprland to focus the next window (see tmux/hypr-nav.conf and
--     config/nvim/lua/custom/plugins/tmux-navigator.lua).
--   * Everywhere else Hyprland takes the keys itself. Apps lose their own
--     Ctrl+H/J/K/L (in Chromium: history, downloads, link search, address bar).

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
  if not window then
    return false
  end

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

local focus_keys = {
  { key = "H", direction = "l", name = "left" },
  { key = "J", direction = "d", name = "below" },
  { key = "K", direction = "u", name = "above" },
  { key = "L", direction = "r", name = "right" },
}

local focus_binds = {}
for _, entry in ipairs(focus_keys) do
  focus_binds[#focus_binds + 1] = hl.bind(
    "CTRL + " .. entry.key,
    hl.dsp.focus({ direction = entry.direction }),
    { description = "Focus on " .. entry.name .. " window" }
  )
end

local function sync_focus_binds(window)
  local enabled = not is_terminal(window)
  for _, bind in ipairs(focus_binds) do
    bind:set_enabled(enabled)
  end
end

hl.on("window.active", sync_focus_binds)
sync_focus_binds(hl.get_active_window())

-- Reachable from `hyprctl eval` for checking and debugging.
o.personal = { focus_binds = focus_binds }

-- Startup layout: terminal on workspace 1, browser on workspace 2 --------------
--
-- The launchers hand their app to systemd, so Hyprland cannot follow the
-- process to place its window. A window rule does the placing instead, and is
-- switched off once the first matching window has opened (or after a minute),
-- so windows opened later land on whatever workspace is in view.

function o.personal.open_on_workspace(class, workspace, command)
  local rule = hl.window_rule({ match = { class = class }, workspace = workspace .. " silent" })
  local pending = true

  local function done()
    if pending then
      pending = false
      rule:set_enabled(false)
    end
  end

  hl.on("window.open", function(window)
    if pending and window and (window.class or ""):find(class) then
      -- Leave the rule on for a moment: it is applied as the window maps.
      hl.timer(done, { timeout = 2000, type = "oneshot" })
    end
  end)
  hl.timer(done, { timeout = 60000, type = "oneshot" })

  hl.exec_cmd(command)
end

-- Try it without a reboot: hyprctl eval 'o.personal.startup_layout()'
function o.personal.startup_layout()
  o.personal.open_on_workspace("org.omarchy.terminal", 1, "omarchy-launch-terminal")
  -- Follows the default browser (omarchy default browser <name>).
  o.personal.open_on_workspace("(chromium|google-chrome.*)", 2, "omarchy-launch-browser")
end

hl.on("hyprland.start", o.personal.startup_layout)
