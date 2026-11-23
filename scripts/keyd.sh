#!/usr/bin/env bash
# Linux counterpart of the Mac's Karabiner setup: install keyd and apply
# keyd/default.conf (Caps Lock = Escape when tapped, Control when held).
# Safe to re-run; re-run it after editing keyd/default.conf.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIRKS=/etc/libinput/local-overrides.quirks

sudo pacman -S --needed --noconfirm keyd
sudo install -Dm644 "$DOTFILES_DIR/keyd/default.conf" /etc/keyd/default.conf

# libinput reads a single overrides file, so leave one we did not write alone
if [ ! -e "$QUIRKS" ] || grep -q 'scripts/keyd.sh' "$QUIRKS"; then
  sudo install -Dm644 "$DOTFILES_DIR/keyd/libinput.quirks" "$QUIRKS"
else
  echo "==> $QUIRKS exists; add the section from keyd/libinput.quirks by hand"
fi

sudo systemctl enable --now keyd
sudo keyd reload
echo "==> keyd active: Caps Lock is Escape (tap) / Control (hold)"
