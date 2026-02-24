MACHINE_NAME=$(hostname)

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH=~/bin:~/.local/bin:$PATH

# ZSH_THEME=""
#
# if [[ "$MACHINE_NAME" == *"MacBook-Pro"* ]]; then
#     ZSH_THEME="af-magic"
# elif [[ "$MACHINE_NAME" == *"mini1"* ]]; then
#     ZSH_THEME="agnoster"
# elif [[ "$MACHINE_NAME" == *"mini2"* ]]; then
#     ZSH_THEME="amuse"
# else
#     ZSH_THEME="af-magic"
# fi

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

export EDITOR='vim'

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

# zsh-autosuggestions (cross-platform)
if [[ -f "$(brew --prefix 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
elif [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
bindkey '^y' autosuggest-accept

# opencode
export PATH=/Users/hyuncholjun/.opencode/bin:$PATH
