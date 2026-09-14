# Formulae
brew "neovim"
brew "tmux"
# --HEAD, not the 1.4.0 release: 1.4.0 only forwards an OSC 52 clipboard copy
# when its content differs from the last one it sent (terminaldisplay.cc compares
# get_clipboard() strings). So copying the same text twice, or text matching what
# mosh last sent, is silently dropped — while the local clipboard has moved on, so
# the paste comes out stale. This is the "drag-copy from a remote tmux stops
# reaching the Mac clipboard" bug. Upstream replaced the content compare with a
# per-copy counter (mosh#1104, fixes mosh#1090); that fix is only on HEAD.
brew "mosh", args: ["HEAD"]
brew "htop"
brew "git"
brew "tldr"
brew "lazygit"
brew "postgresql@16"
brew "ripgrep"
brew "fd"
brew "direnv"
brew "fzf"
brew "gh"
brew "mas"
brew "docker-compose"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "zsh-history-substring-search"
brew "zoxide"
brew "mise"
brew "jq"
brew "ffmpeg"
brew "yazi"
brew "yq"
brew "poppler"
brew "visidata"
brew "duckdb"

# Casks
cask "ghostty"
cask "obsidian"
cask "slack"
cask "google-chrome"
cask "dbeaver-community"
cask "karabiner-elements"
cask "raycast"
cask "opal-composer"
cask "docker-desktop"
cask "hammerspoon"
cask "tailscale-app"
cask "wispr-flow"
# Codex desktop app is discontinued upstream (codex-app cask disabled 2027-07-12);
# the ChatGPT desktop app is its upstream replacement
cask "chatgpt"
cask "font-jetbrains-mono-nerd-font"
