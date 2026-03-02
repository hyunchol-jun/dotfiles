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
4. Install npm global packages (typescript, prettier, pnpm, tsx)
5. Install Claude Code and OpenCode if missing
6. Clone TPM (Tmux Plugin Manager) if missing

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

### Dropbox via rclone NFS

1. Run `rclone config` to set up Dropbox OAuth (remote name: `dropbox-implentio`)
2. Mount with `dbmount`, then browse `~/Dropbox` in yazi
3. Unmount with `dbumount`

### Reload tmux config

```bash
tmux source ~/.tmux.conf
```

## Worktree-Tmux (Neovim Plugin)

A custom Neovim plugin for managing git worktrees with tmux integration. Provides `:WorktreeCreate`, `:WorktreeSwitch`, `:WorktreeDelete`, and `:WorktreeMerge` commands.

### Setting up a bare repo

The plugin works best with bare-cloned repositories. To set one up:

```bash
# 1. Clone as bare repo
git clone --bare <repo-url> ~/path/to/repo.git

# 2. Fix the fetch refspec (bare clones don't set this up by default)
cd ~/path/to/repo.git
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# 3. Fetch remote branches
git fetch origin

# 4. Set the default branch HEAD ref (used by the plugin to detect the default branch)
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 5. Create a worktree for the main branch
git worktree add main main
```

This gives you a structure like:

```
~/path/to/repo.git/       # bare repo (git data only)
~/path/to/repo.git/main/  # main branch worktree
```

New worktrees created via `:WorktreeCreate` will appear as siblings (e.g. `~/path/to/repo.git/feature-branch/`).

### Project-specific config

Per-project overrides (tmux mode, custom layouts, pane commands) are defined in `config/nvim/lua/custom/worktree-tmux-projects.lua`. The key must match the git repository directory name (e.g. `repo` from `repo.git`).

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
install.conf.yaml         # Dotbot symlink configuration
zshrc                     # Zsh configuration
tmux.conf                 # Tmux configuration
```
