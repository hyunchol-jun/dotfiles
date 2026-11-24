#!/bin/sh
# Runs before Dotbot links anything. Omarchy ships its own Neovim, Ghostty and
# tmux configs in ~/.config; Dotbot will not replace a real directory, and tmux
# would load Omarchy's ~/.config/tmux/tmux.conf on top of ours. Move them to
# ~/.config-omarchy-backup so ours take their place. Idempotent; a no-op on
# machines without Omarchy.

[ -d "$HOME/.config/omarchy" ] || exit 0

BACKUP="$HOME/.config-omarchy-backup"
for name in nvim ghostty tmux; do
  dir="$HOME/.config/$name"
  # Already our symlink, or not there at all
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then
    continue
  fi
  if [ -e "$BACKUP/$name" ]; then
    echo "omarchy-prepare: $dir exists and $BACKUP/$name is already taken; move it by hand" >&2
    exit 1
  fi
  mkdir -p "$BACKUP"
  mv "$dir" "$BACKUP/$name"
  echo "moved $dir to $BACKUP/$name"
done
