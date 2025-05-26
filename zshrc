MACHINE_NAME=$(hostname)

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH=~/bin:~/Library/Python/3.8/bin:~/Library/Python/3.9/bin:/usr/local/mysql/bin:$PATH

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

eval "$(zoxide init --cmd cd zsh)"

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

export EDITOR='vim'

# Added for Android development
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools

export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home

export SOPS_AGE_KEY_FILE=~/Implentio/implentio-local-dev-key.txt

# Created by `pipx` on 2024-05-01 01:05:58
export PATH="$PATH:~/.local/bin"

# Nix related
export PATH="$NIX_LINK/bin:/nix/var/nix/profiles/default/bin:$PATH"
export PATH="$HOME/.nix-profile/bin:$PATH"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# For direnv to work properly it needs to be hooked into the shell.
eval "$(direnv hook zsh)"

# Load file storing api keys for things like AI
if [[ -f ~/.api_keys ]]; then
  source ~/.api_keys
fi

source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
