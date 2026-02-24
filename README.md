# dotfiles

Cross-platform dotfiles managed with [Dotbot](https://github.com/anishathalye/dotbot) (symlinks), [Homebrew](https://brew.sh)/[pacman](https://wiki.archlinux.org/title/Pacman) (packages), and [mise](https://mise.jdx.dev) (runtime versions).

Supports **macOS** and **Arch Linux**.

## Installation

```bash
git clone git@github.com:hyunchol-jun/dotfiles.git
cd dotfiles
./scripts/bootstrap.sh
```

This will:
1. Install platform packages (Homebrew + Brewfile on macOS, pacman + yay on Arch)
2. Run Dotbot to symlink config files
3. Install runtimes via mise (Node, Java, Python)
4. Clone TPM (Tmux Plugin Manager) if missing

## Runtime Management (mise)

mise manages Node, Java, and Python versions. Configuration lives in `config/mise/config.toml`.

```bash
mise install          # Install all configured runtimes
mise ls               # List installed versions
mise use node@22      # Switch Node version (updates config)
mise use java@zulu-17 # Switch Java version
```

Per-project overrides: add a `.mise.toml` in any project directory to pin specific versions for that project.

## After Install

### Tmux plugins

1. Open tmux
2. Press `prefix + I` to install plugins via TPM

### Reload tmux config

```bash
tmux source ~/.tmux.conf
```

## Structure

```
Brewfile                  # macOS packages (Homebrew)
scripts/
  bootstrap.sh            # Entry point: OS detection + common setup
  macos.sh                # macOS: Homebrew, brew bundle, defaults
  arch.sh                 # Arch: pacman, yay, AUR packages
config/
  mise/config.toml        # Runtime versions (node, java, python)
  nvim/                   # Neovim config
  ohmyposh/               # Oh My Posh prompt theme
install.conf.yaml         # Dotbot symlink configuration
zshrc                     # Zsh configuration
tmux.conf                 # Tmux configuration
```
