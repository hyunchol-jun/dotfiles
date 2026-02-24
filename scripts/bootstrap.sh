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
if mise ls --missing | grep -q .; then
  echo "==> Installing mise runtimes..."
  mise install
else
  echo "==> mise runtimes already installed"
fi

# npm global packages
NPM_GLOBALS=(typescript prettier pnpm tsx)
missing=()
for pkg in "${NPM_GLOBALS[@]}"; do
  if ! npm ls -g "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "==> Installing npm global packages: ${missing[*]}"
  npm install -g "${missing[@]}"
else
  echo "==> npm global packages already installed"
fi

# Claude Code
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
else
  echo "==> Claude Code already installed"
fi

# OpenCode
if ! command -v opencode &>/dev/null; then
  echo "==> Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
else
  echo "==> OpenCode already installed"
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
