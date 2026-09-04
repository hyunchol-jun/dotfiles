#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Detected dotfiles directory: $DOTFILES_DIR"

# Non-interactive shells (ssh) don't source zshrc, so put brew,
# mise-managed tools (node/npm), and curl-installed binaries
# (claude, omp, codex, opencode) on PATH explicitly
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
command -v mise &>/dev/null && eval "$(mise activate bash --shims)"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

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

# rclone (installed from official binary on macOS for FUSE mount support)
if ! command -v rclone &>/dev/null; then
  if [ -t 0 ]; then
    echo "==> Installing rclone..."
    sudo -v ; curl https://rclone.org/install.sh | sudo bash
  else
    echo "==> Skipping rclone (needs sudo; run bootstrap.sh in a terminal to install)"
  fi
else
  echo "==> rclone already installed"
fi

# Claude Code
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
else
  echo "==> Claude Code already installed"
fi

# Claude Code MCP servers
echo "==> Configuring Claude Code MCP servers..."
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest || true
# TODO: Add Exa MCP server once API key is set up
# claude mcp add exa --scope user -e EXA_API_KEY=your-key-here -- npx -y exa-mcp-server@latest

# OpenCode
if ! command -v opencode &>/dev/null; then
  echo "==> Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
else
  echo "==> OpenCode already installed"
fi

# Claude Code settings: shared keys live in .claude/settings.seed.json and are
# merged into the live file on every run (seed wins on shared keys). Machine-
# specific keys the app writes (model, modelSettings, effortLevel) are kept.
CLAUDE_CFG="$HOME/.claude/settings.json"
CLAUDE_SEED="$DOTFILES_DIR/.claude/settings.seed.json"
mkdir -p "$HOME/.claude"
if [ -L "$CLAUDE_CFG" ]; then
  echo "==> Converting Claude settings symlink to a real file..."
  cp -L "$CLAUDE_CFG" "$CLAUDE_CFG.tmp" && mv -f "$CLAUDE_CFG.tmp" "$CLAUDE_CFG"
fi
if [ ! -e "$CLAUDE_CFG" ]; then
  echo "==> Seeding Claude settings..."
  cp "$CLAUDE_SEED" "$CLAUDE_CFG"
else
  echo "==> Merging shared Claude settings..."
  jq -s '.[0] * .[1]' "$CLAUDE_CFG" "$CLAUDE_SEED" > "$CLAUDE_CFG.tmp" && mv -f "$CLAUDE_CFG.tmp" "$CLAUDE_CFG"
fi

# OpenAI Codex
if ! command -v codex &>/dev/null; then
  echo "==> Installing OpenAI Codex..."
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
else
  echo "==> OpenAI Codex already installed"
fi

# Codex config: seed once, then the app owns the file. Older setups symlinked
# it into the repo; replace that symlink with a real copy so pulls never conflict.
CODEX_CFG="$HOME/.codex/config.toml"
mkdir -p "$HOME/.codex"
if [ -L "$CODEX_CFG" ]; then
  echo "==> Converting Codex config symlink to a real file..."
  cp -L "$CODEX_CFG" "$CODEX_CFG.tmp" && mv -f "$CODEX_CFG.tmp" "$CODEX_CFG"
elif [ ! -e "$CODEX_CFG" ]; then
  echo "==> Seeding Codex config..."
  cp "$DOTFILES_DIR/.codex/config.seed.toml" "$CODEX_CFG"
else
  echo "==> Codex config already present"
fi

# oh-my-pi (omp)
if ! command -v omp &>/dev/null; then
  echo "==> Installing oh-my-pi..."
  curl -fsSL https://omp.sh/install | sh
else
  echo "==> oh-my-pi already installed"
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
