#!/usr/bin/env bash
# Keep a laptop running with the lid closed while it is plugged in (on battery
# the lid still suspends). Safe to re-run.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo install -Dm644 "$DOTFILES_DIR/systemd/logind-lid.conf" /etc/systemd/logind.conf.d/50-lid-on-mains.conf
# SIGHUP makes logind re-read its config; restarting it would end the session.
sudo systemctl kill -s HUP systemd-logind
echo "==> lid is ignored while plugged in"
