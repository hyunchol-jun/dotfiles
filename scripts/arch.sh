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
  fd \
  direnv \
  fzf \
  github-cli \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting \
  zsh-history-substring-search \
  jq \
  mosh \
  zoxide \
  tailscale \
  yazi \
  rclone \
  visidata

# Omarchy ships ttf-jetbrains-mono-nerd-basic, which provides this name and
# conflicts with the full package, so only install when nothing provides it
if ! pacman -Q ttf-jetbrains-mono-nerd &>/dev/null; then
  sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd
fi

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

# zsh as the login shell
ZSH_PATH="$(command -v zsh)"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  echo "==> Changing login shell to zsh..."
  sudo chsh -s "$ZSH_PATH" "$USER"
fi

echo "==> Arch Linux setup complete!"
