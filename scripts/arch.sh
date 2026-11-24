#!/usr/bin/env bash
set -euo pipefail

# Update system. Omarchy blocks a direct `pacman -Syu` with a pacman hook: its
# own updater takes the snapshot and runs the migrations a bare upgrade skips.
echo "==> Updating system..."
if command -v omarchy-update &>/dev/null; then
  omarchy-update -y
else
  sudo pacman -Syu --noconfirm
fi

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
  "$(dirname "${BASH_SOURCE[0]}")/chrome.sh"
fi

# Keyboard remaps (the Linux counterpart of Karabiner on the Mac)
"$(dirname "${BASH_SOURCE[0]}")/keyd.sh"

# Tailscale: the package only installs the daemon. Start it now and on boot;
# joining the tailnet is a one-time `sudo tailscale up` by hand (it prints a
# login link).
if ! systemctl is-enabled --quiet tailscaled 2>/dev/null; then
  echo "==> Enabling tailscaled..."
  sudo systemctl enable --now tailscaled
fi

# zsh as the login shell
ZSH_PATH="$(command -v zsh)"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  echo "==> Changing login shell to zsh..."
  sudo chsh -s "$ZSH_PATH" "$USER"
fi

# Git identity, the same as on the Mac (whose ~/.gitconfig is not tracked).
# Omarchy's ~/.config/git/config carries no user section, so commits fail
# until this is set.
git config --global user.name >/dev/null || git config --global user.name "Joseph Jun"
git config --global user.email >/dev/null || git config --global user.email "joseph.hyunchol.jun@gmail.com"
git config --global init.defaultBranch main

echo "==> Arch Linux setup complete!"
