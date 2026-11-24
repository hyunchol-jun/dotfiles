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
5. Install Claude Code if missing
6. Clone TPM (Tmux Plugin Manager) if missing

### Arch Linux / Omarchy

On a machine without a GitHub SSH key, clone over HTTPS instead (the repo must
live at `~/dotfiles`; several scripts refer to that path):

```bash
git clone https://github.com/hyunchol-jun/dotfiles.git ~/dotfiles
~/dotfiles/scripts/bootstrap.sh   # in a terminal on the machine itself: it asks for the sudo password
```

Run it from the desktop session, not over SSH, so the GUI apps (Ghostty and
friends) are installed too. Then log out and back in for zsh.

On [Omarchy](https://omarchy.org) the same command also sets up the desktop:

| What | Where |
|---|---|
| System update through `omarchy-update` (a direct `pacman -Syu` is blocked there) | `scripts/arch.sh` |
| Caps Lock = Escape on tap, Control on hold (keyd) | `keyd/default.conf`, `scripts/keyd.sh` |
| Omarchy's own nvim, ghostty and tmux configs moved to `~/.config-omarchy-backup` | `scripts/omarchy-prepare.sh` |
| Configs linked one tool at a time into the existing `~/.config` | Linux block of `install.conf.yaml` |
| Hyprland: natural scrolling, no gaps, 1px border, no animations, always tiling, Ctrl+h/j/k/l focus across Neovim, tmux and app windows, Ctrl+1..0 workspaces, Alt+h/j/k/l/m/c window placement, terminal and browser opened on workspaces 1 and 2 at startup, no idling while plugged in | `config/hypr/personal.lua` |
| Google Chrome installed and set as the default browser, Chromium removed | `scripts/chrome.sh` |
| Black wallpaper, kept across theme changes | `omarchy/`, `scripts/hypr-setup.sh` |

After editing `config/hypr/personal.lua` run `hyprctl reload`; after editing
`keyd/default.conf` run `scripts/keyd.sh`.

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

Bootstrap installs them. To add one later, press `prefix + I` inside tmux.

### Dropbox via rclone NFS

1. Run `rclone config` to set up Dropbox OAuth (remote name: `dropbox-implentio`)
2. Mount with `dbmount`, then browse `~/Dropbox` in yazi
3. Unmount with `dbumount`

### Reload tmux config

```bash
tmux source ~/.tmux.conf
```

## Worktrees with tmux windows (`wt`)

`bin/wt` creates a git worktree together with its tmux window, and removes or merges it again (`wt new`, `open`, `ls`, `rm`, `merge`, and `gc` to clear out worktrees whose PR is merged; run `wt` for the usage). It has three callers: the command line, the Neovim plugin (`:WorktreeCreate`, `:WorktreeSwitch`, `:WorktreeDelete`, `:WorktreeMerge` on `<leader>wt{c,s,d,m}`, a thin UI over `wt`), and agents through the `wt` skill.

`bin/tmux-split` is the same idea for panes: `prefix+|`, `prefix+-` and the `tmux-split` skill all open panes through it, which holds each window at two panes.

`scripts/tmux-menu.sh` provides tap menus for clients without a keyboard (iPad): tap the left end of the status bar for sessions, agents, windows and pane actions, the right end for the session list.

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

# 4. Set the default branch HEAD ref (used by `wt` to detect the default branch)
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 5. Create a worktree for the main branch
git worktree add main main
```

This gives you a structure like:

```
~/path/to/repo.git/       # bare repo (git data only)
~/path/to/repo.git/main/  # main branch worktree
```

New worktrees created via `wt new` or `:WorktreeCreate` will appear as siblings (e.g. `~/path/to/repo.git/feature-branch/`).

### Project-specific config

Per-project overrides (tmux mode, agent command, files symlinked from the main worktree) live in `config/wt/projects/<project>.sh`, sourced by `wt` as bash. `<project>` is the git repository directory name (e.g. `repo` from `repo.git`). The knobs and their defaults are listed at the top of `bin/wt`.

## Structure

```
Brewfile                  # macOS packages (Homebrew)
scripts/
  bootstrap.sh            # Entry point: OS detection + common setup
  macos.sh                # macOS: Homebrew, brew bundle, defaults
  arch.sh                 # Arch: pacman, yay, AUR packages
  keyd.sh                 # Arch: keyboard remaps (keyd)
  omarchy-prepare.sh      # Omarchy: move its stock configs aside before linking
  hypr-setup.sh           # Omarchy: hook config/hypr/personal.lua into Hyprland, wallpaper
keyd/                     # keyd config (Linux counterpart of Karabiner)
omarchy/                  # Black wallpaper and the hook that keeps it
tmux/hypr-nav.conf        # tmux side of Ctrl+h/j/k/l across app windows (Hyprland only)
config/
  mise/config.toml        # Runtime versions (node, java, python)
  nvim/                   # Neovim config
  hypr/personal.lua       # Hyprland settings for Omarchy
install.conf.yaml         # Dotbot symlink configuration
zshrc                     # Zsh configuration
tmux.conf                 # Tmux configuration
```
