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
    dbeaver \
    slack-desktop
  "$(dirname "${BASH_SOURCE[0]}")/chrome.sh"
fi

# Keyboard remaps (the Linux counterpart of Karabiner on the Mac)
"$(dirname "${BASH_SOURCE[0]}")/keyd.sh"

# Tailscale: start the daemon now and on boot, then join the tailnet. Joining
# prints a login link and waits for it to be approved in a browser (any
# machine's will do), so it is skipped when there is no terminal to show it.
# --operator lets later `tailscale` commands run without sudo.
if ! systemctl is-enabled --quiet tailscaled 2>/dev/null; then
  echo "==> Enabling tailscaled..."
  sudo systemctl enable --now tailscaled
fi
if tailscale status &>/dev/null; then
  echo "==> Tailscale already connected"
elif [ -t 0 ]; then
  echo "==> Joining the tailnet (open the link below to approve this machine)..."
  sudo tailscale up --operator="$USER"
else
  echo "==> Skipping the Tailscale login (run: sudo tailscale up --operator=$USER)"
fi

# SSH key: what the mini1/mini2 aliases in zshrc log in with. A new key opens
# nothing until a machine the minis already trust hands it to them, so the
# command for that is printed.
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  echo "==> Generating an SSH key..."
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "$USER@$(uname -n)" -f "$SSH_KEY"
  echo "    To let this machine into mini1 and mini2, run on a machine they trust:"
  echo "      ~/dotfiles/scripts/trust-machine.sh $USER@<this machine's address>"
fi

# Dotfiles pushes go over SSH. The repo is cloned over HTTPS (public, so pulls
# need no login) and the gh login is the work account, which cannot push here.
# Pushing works once ~/.ssh/id_ed25519.pub is added to the GitHub account that
# owns the repo: https://github.com/settings/ssh/new
DOTFILES_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_URL="$(git -C "$DOTFILES_REPO" remote get-url origin)"
if [[ "$DOTFILES_URL" == https://github.com/* ]]; then
  DOTFILES_PUSH_URL="git@github.com:${DOTFILES_URL#https://github.com/}"
  if [ "$(git -C "$DOTFILES_REPO" remote get-url --push origin)" != "$DOTFILES_PUSH_URL" ]; then
    echo "==> Pointing dotfiles pushes at SSH..."
    git -C "$DOTFILES_REPO" remote set-url --push origin "$DOTFILES_PUSH_URL"
  fi
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
