MACHINE_NAME=$(hostname)

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH=~/bin:~/.local/bin:$PATH

eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/main.toml)"

eval "$(zoxide init zsh)"

# Vim functionality enabled
bindkey -v

# Aliases
alias ll="ls -lah"
alias gs="git status"
alias gdt="git difftool --tool=vimdiff -y"
alias mv="mv -i"
alias "gll"="git log --graph --pretty=oneline --abbrev-commit"
alias python=python3
alias pip=pip3
alias v="nvim"

alias pgstart='~/dotfiles/postgres-external-scripts/pg-toggle.sh start'
alias pgstop='~/dotfiles/postgres-external-scripts/pg-toggle.sh stop'
alias pgstatus='~/dotfiles/postgres-external-scripts/pg-toggle.sh status'

export EDITOR='nvim'

# Added for Android development
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools

export SOPS_AGE_KEY_FILE=~/Implentio/implentio-local-dev-key.txt

# mise (runtime version manager)
eval "$(mise activate zsh)"

# For direnv to work properly it needs to be hooked into the shell.
eval "$(direnv hook zsh)"

# Load file storing api keys for things like AI
if [[ -f ~/.api_keys ]]; then
  source ~/.api_keys
fi

# Cache brew prefix for faster startup
BREW_PREFIX=$(brew --prefix 2>/dev/null)

# fzf shell integration (Ctrl+R, Ctrl+T, Alt+C)
if [[ -n "$BREW_PREFIX" ]]; then
  eval "$($BREW_PREFIX/bin/fzf --zsh 2>/dev/null)"
fi

# zsh-autosuggestions (cross-platform)
if [[ -f "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
elif [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
bindkey '^y' autosuggest-accept

# zsh-history-substring-search
if [[ -f "$BREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "$BREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh"
elif [[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
fi
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# zsh-syntax-highlighting (must be sourced last)
if [[ -f "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
elif [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# opencode
export PATH=/Users/hyuncholjun/.opencode/bin:$PATH
