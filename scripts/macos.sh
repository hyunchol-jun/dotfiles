#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Press any key after Xcode CLI tools installation completes..."
  read -n 1 -s
fi

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install packages from Brewfile
echo "==> Checking Brewfile dependencies..."
export HOMEBREW_NO_AUTO_UPDATE=1
if brew bundle check --file="$DOTFILES_DIR/Brewfile" &>/dev/null; then
  echo "==> All Brewfile dependencies satisfied, skipping install."
else
  echo "==> Running brew bundle..."
  if ! brew bundle --file="$DOTFILES_DIR/Brewfile" --no-upgrade --no-lock; then
    echo "==> Some Brewfile entries failed (may need sudo or MAS login). Continuing..."
  fi
fi

# macOS defaults
echo "==> Applying macOS defaults..."

changed=0

apply_default() {
  local current
  current=$(defaults read "$1" "$2" 2>/dev/null) || current=""
  if [[ "$current" != "$3" ]]; then
    shift 3
    defaults write "$@"
    changed=1
  fi
}

apply_default_currentHost() {
  local current
  current=$(defaults -currentHost read "$1" "$2" 2>/dev/null) || current=""
  if [[ "$current" != "$3" ]]; then
    shift 3
    defaults -currentHost write "$@"
    changed=1
  fi
}

# Dock: autohide
apply_default com.apple.dock autohide 1 \
  com.apple.dock autohide -bool true

# Dock: minimize effect
apply_default com.apple.dock mineffect scale \
  com.apple.dock mineffect -string "scale"

# Dark mode
apply_default NSGlobalDomain AppleInterfaceStyle Dark \
  NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Fast key repeat
apply_default NSGlobalDomain KeyRepeat 2 \
  NSGlobalDomain KeyRepeat -int 2
apply_default NSGlobalDomain InitialKeyRepeat 15 \
  NSGlobalDomain InitialKeyRepeat -int 15

# Hide menu bar
apply_default NSGlobalDomain _HIHideMenuBar 1 \
  NSGlobalDomain _HIHideMenuBar -bool true

# Trackpad: tap to click
apply_default com.apple.AppleMultitouchTrackpad Clicking 1 \
  com.apple.AppleMultitouchTrackpad Clicking -bool true
apply_default_currentHost NSGlobalDomain com.apple.mouse.tapBehavior 1 \
  NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Disable natural scrolling
apply_default NSGlobalDomain com.apple.swipescrolldirection 0 \
  NSGlobalDomain com.apple.swipescrolldirection -bool false

# Finder: show all filename extensions
apply_default NSGlobalDomain AppleShowAllExtensions 1 \
  NSGlobalDomain AppleShowAllExtensions -bool true

# Finder: show path bar
apply_default com.apple.finder ShowPathbar 1 \
  com.apple.finder ShowPathbar -bool true

# Restart affected applications only if something changed
if [[ "$changed" -eq 1 ]]; then
  echo "==> Restarting Dock, Finder, and SystemUIServer..."
  killall Dock Finder SystemUIServer 2>/dev/null || true
else
  echo "==> Defaults already up to date, skipping restart."
fi

echo "==> macOS setup complete!"
