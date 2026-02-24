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
echo "==> Running brew bundle..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

# macOS defaults
echo "==> Applying macOS defaults..."

# Dock: autohide
defaults write com.apple.dock autohide -bool true

# Dock: minimize effect
defaults write com.apple.dock mineffect -string "scale"

# Dark mode
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Fast key repeat
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Hide menu bar
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# Trackpad: tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Disable natural scrolling
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Finder: show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Restart affected applications
echo "==> Restarting Dock, Finder, and SystemUIServer..."
killall Dock Finder SystemUIServer 2>/dev/null || true

echo "==> macOS setup complete!"
