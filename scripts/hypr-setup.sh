#!/bin/sh
# Hook config/hypr/personal.lua into Omarchy's Hyprland config by adding one
# require line to ~/.config/hypr/hyprland.lua. Idempotent; a no-op on machines
# without that file (macOS, plain Arch without Omarchy).

CFG="$HOME/.config/hypr/hyprland.lua"
[ -f "$CFG" ] || exit 0
grep -q 'require("hypr.personal")' "$CFG" && exit 0

printf '\n-- Personal settings tracked in ~/dotfiles (config/hypr/personal.lua).\nrequire("hypr.personal")\n' >> "$CFG"
echo "hooked hypr.personal into $CFG"
