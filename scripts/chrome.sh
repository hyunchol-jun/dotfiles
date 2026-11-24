#!/usr/bin/env bash
# Install Google Chrome and make it the default browser. Safe to re-run.
# Run it from the desktop session: on Omarchy it uses Omarchy's own installer,
# which also sets Chrome's Wayland flags and theme.
set -euo pipefail

if command -v omarchy-default-browser &>/dev/null; then
  if [ "$(omarchy-default-browser)" = chrome ] && command -v google-chrome-stable &>/dev/null; then
    echo "==> Chrome already installed and default"
    exit 0
  fi
  # --install: install here instead of opening a separate terminal for it
  omarchy-default-browser --install chrome
else
  yay -S --needed --noconfirm google-chrome
  xdg-settings set default-web-browser google-chrome.desktop
fi

echo "==> Chrome is the default browser"
