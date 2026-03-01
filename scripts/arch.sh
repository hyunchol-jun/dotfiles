#!/usr/bin/env bash
set -euo pipefail

# Update system
echo "==> Updating system..."
sudo pacman -Syu --noconfirm

# Install packages via pacman
echo "==> Installing pacman packages..."
sudo pacman -S --needed --noconfirm \
  neovim \
  tmux \
  htop \
  git \
  tldr \
  lazygit \
  postgresql \
  typescript-language-server \
  ripgrep \
  direnv \
  fzf \
  github-cli \
  zsh \
  zsh-autosuggestions \
  zoxide \
  tailscale \
  yazi \
  rclone \
  ttf-jetbrains-mono-nerd

# Install yay (AUR helper)
if ! command -v yay &>/dev/null; then
  echo "==> Installing yay..."
  sudo pacman -S --needed --noconfirm git base-devel
  TMPDIR=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay"
  (cd "$TMPDIR/yay" && makepkg -si --noconfirm)
  rm -rf "$TMPDIR"
fi

# Install AUR packages via yay
echo "==> Installing AUR packages..."
yay -S --needed --noconfirm \
  mise-bin \
  oh-my-posh-bin

# GUI apps (only if a desktop environment is detected)
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  echo "==> Installing GUI applications..."
  sudo pacman -S --needed --noconfirm ghostty
  yay -S --needed --noconfirm \
    obsidian \
    intellij-idea-community-edition \
    dbeaver
fi

echo "==> Arch Linux setup complete!"
