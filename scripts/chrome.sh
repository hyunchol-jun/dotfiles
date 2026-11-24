#!/usr/bin/env bash
# Install Google Chrome, make it the default browser and remove Chromium.
# Safe to re-run. Run it from the desktop session: on Omarchy it uses Omarchy's
# own installer, which also sets Chrome's Wayland flags and theme.
set -euo pipefail

if command -v omarchy-default-browser &>/dev/null; then
  if [ "$(omarchy-default-browser)" = chrome ] && command -v google-chrome-stable &>/dev/null; then
    echo "==> Chrome already installed and default"
  else
    # --install: install here instead of opening a separate terminal for it
    omarchy-default-browser --install chrome
  fi
else
  yay -S --needed --noconfirm google-chrome
  xdg-settings set default-web-browser google-chrome.desktop
fi

# Chromium comes with Omarchy. Nothing depends on the package, and Omarchy's
# web apps run in the default browser. Only once Chrome is really in place;
# the profile in ~/.config/chromium is left alone.
if command -v google-chrome-stable &>/dev/null && pacman -Qq chromium &>/dev/null; then
  echo "==> Removing Chromium..."
  sudo pacman -Rns --noconfirm chromium
fi

echo "==> Chrome is the default browser"
