#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Detected dotfiles directory: $DOTFILES_DIR"

# Platform-specific setup
case "$(uname -s)" in
  Darwin)
    echo "==> macOS detected"
    "$DOTFILES_DIR/scripts/macos.sh"
    ;;
  Linux)
    if [ -f /etc/arch-release ]; then
      echo "==> Arch Linux detected"
      "$DOTFILES_DIR/scripts/arch.sh"
    else
      echo "Unsupported Linux distro"
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

# Dotbot symlinks
echo "==> Running Dotbot..."
"$DOTFILES_DIR/install"

# mise runtimes
echo "==> Installing mise runtimes..."
mise install

# Claude Code
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
else
  echo "==> Claude Code already installed"
fi

# TPM (Tmux Plugin Manager)
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  echo "==> Cloning TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  echo "==> TPM already installed"
fi

echo "==> Bootstrap complete!"
