#!/bin/sh
# Omarchy desktop setup. Idempotent; a no-op on machines without Omarchy's
# Hyprland config (macOS, plain Arch).
#   * hooks config/hypr/personal.lua into Hyprland with one require line in
#     ~/.config/hypr/hyprland.lua
#   * sets the plain black wallpaper (omarchy/black-background-hook keeps it
#     across theme changes)

CFG="$HOME/.config/hypr/hyprland.lua"
[ -f "$CFG" ] || exit 0

BLACK="$HOME/dotfiles/omarchy/black.png"
CURRENT="$HOME/.local/state/omarchy/current/background"
if command -v omarchy-theme-bg-set >/dev/null 2>&1 && [ "$(readlink "$CURRENT" 2>/dev/null)" != "$BLACK" ]; then
  # Sets the link even when the desktop is not running to be told about it.
  omarchy-theme-bg-set "$BLACK" >/dev/null 2>&1 || true
  echo "wallpaper set to black"
fi

grep -q 'require("hypr.personal")' "$CFG" && exit 0

printf '\n-- Personal settings tracked in ~/dotfiles (config/hypr/personal.lua).\nrequire("hypr.personal")\n' >> "$CFG"
echo "hooked hypr.personal into $CFG"
