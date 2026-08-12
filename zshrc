MACHINE_NAME=$(hostname)

# mini1 (8GB): cap node heaps + test parallelism (2026-08-06 watchdog panic)
if [[ $MACHINE_NAME == mini1* ]]; then
    export NODE_OPTIONS="--max-old-space-size=4096"
    export VITEST_MAX_THREADS=2
    export VITEST_MAX_FORKS=2
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH=~/bin:~/.local/bin:$PATH

# Nix
[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Prompt
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' formats ' %F{yellow}%b%u%c%f'
setopt PROMPT_SUBST
PROMPT='%F{blue}%~%f${vcs_info_msg_0_} %F{magenta}❯%f '

eval "$(zoxide init zsh)"

# Vim functionality enabled
bindkey -v

# Aliases
alias ll="ls -lah"
alias gs="git status"
alias gdt="git difftool --tool=vimdiff -y"
alias mv="mv -i"
alias "gll"="git log --graph --pretty=oneline --abbrev-commit"
cherry-now() { git cherry-pick "$1" && git commit --amend --no-edit --date=now; }
alias python=python3
alias pip=pip3
alias v="nvim"
alias y="yazi"
alias cc="claude --dangerously-skip-permissions"
alias cx="codex --yolo"
alias oc="opencode"

# AWS SSO login without opening a browser: prints a URL + code to complete
# on any machine (open it in an incognito window to use different credentials).
# Same as the stack repo's `login` wrapper, plus --use-device-code.
aws-login-headless() {
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    local profile
    profile=$(grep profile "$config" | sed 's/^\[profile \(.*\)\]/\1/' | fzf)
    if [ -z "$profile" ]; then
        echo "No profile selected"
        return 1
    fi
    # --use-device-code exists only from CLI 2.22.0; before that, device code
    # is the default flow and --no-browser stops the browser from opening.
    autoload -Uz is-at-least
    local ver="${$(aws --version 2>&1)#aws-cli/}"
    local flag="--no-browser"
    is-at-least 2.22.0 "${ver%% *}" && flag="--use-device-code"
    aws --profile "$profile" sso login "$flag"
}

alias pgstart='~/dotfiles/postgres-external-scripts/pg-toggle.sh start'
alias pgstop='~/dotfiles/postgres-external-scripts/pg-toggle.sh stop'
alias pgstatus='~/dotfiles/postgres-external-scripts/pg-toggle.sh status'

alias dbls='rclone ls dropbox-implentio:/'
alias dbcat='rclone cat'
alias dbcp='rclone copy'
alias dbmount='mkdir -p ~/Dropbox && rclone serve nfs dropbox-implentio:/ --read-only --vfs-cache-mode full --addr :2049 &; sleep 1 && mount_nfs -o port=2049,mountport=2049,tcp,vers=3 localhost:/ ~/Dropbox'
alias dbumount='umount ~/Dropbox && kill $(lsof -ti :2049) 2>/dev/null'

alias dbt-r='~/dotfiles/scripts/implentio-custom-db-tunnel.sh -l 9001 -d app -h localhost -r Reader'
alias dbt-rw='~/dotfiles/scripts/implentio-custom-db-tunnel.sh -l 9001 -d app -h localhost -r Superuser'

# attach to mini1's tmux over LAN (falls back to tailscale IP if LAN fails)
alias mini1='ssh -t -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 michaelkang@100.122.37.52 /opt/homebrew/bin/tmux attach || ssh -t -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 michaelkang@100.122.37.52 /opt/homebrew/bin/tmux attach'

# attach to mini2's tmux over tailscale
alias mini2='ssh -t -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 josephjun@100.119.210.87 /opt/homebrew/bin/tmux attach || ssh -t -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 josephjun@100.119.210.87 /opt/homebrew/bin/tmux attach'

# forward ports from mini1 so its dev servers open in this machine's browser
# usage: mini1fwd [thisport:mini1port | port ...]   (default 3000) — ctrl-c to stop
#   mini1fwd 3000            → localhost:3000 here → mini1's 3000
#   mini1fwd 4000:3000 8080  → localhost:4000 here → mini1's 3000, plus 8080 → 8080
mini1fwd() {
  local specs=("${@:-3000}") fwd=() local_p remote_p
  for s in "${specs[@]}"; do
    local_p="${s%%:*}"; remote_p="${s##*:}"
    fwd+=(-L "${local_p}:localhost:${remote_p}")
    echo "http://localhost:${local_p} (this machine) → mini1:${remote_p}"
  done
  echo "(ctrl-c to stop)"
  ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 "${fwd[@]}" michaelkang@100.122.37.52 ||
    ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 "${fwd[@]}" michaelkang@100.122.37.52
}

# same as mini1fwd, for mini2
mini2fwd() {
  local specs=("${@:-3000}") fwd=() local_p remote_p
  for s in "${specs[@]}"; do
    local_p="${s%%:*}"; remote_p="${s##*:}"
    fwd+=(-L "${local_p}:localhost:${remote_p}")
    echo "http://localhost:${local_p} (this machine) → mini2:${remote_p}"
  done
  echo "(ctrl-c to stop)"
  ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 "${fwd[@]}" josephjun@100.119.210.87 ||
    ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 "${fwd[@]}" josephjun@100.119.210.87
}

# copy a file (default: newest Desktop screenshot) to mini1 and put mini1's path
# on this machine's clipboard, so you can cmd-v it into mini1's claude code.
# usage: mini1send            → newest ~/Desktop screenshot
#        mini1send some.png   → that file
mini1send() {
  local src="$1" dest
  if [[ -z "$src" ]]; then
    src=$(print -rl -- ~/Desktop/*.(png|jpg|jpeg)(NDom) 2>/dev/null | head -1)
    [[ -z "$src" ]] && { echo "no image on ~/Desktop"; return 1; }
  fi
  [[ -f "$src" ]] || { echo "no such file: $src"; return 1; }
  # spaces break path detection when pasted (macOS shots also use U+202F), so flatten
  dest="/Users/michaelkang/Desktop/from-mbp/${${src:t}//[^A-Za-z0-9._-]/_}"
  local ssh_opts=(-o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5)
  local host=192.168.219.46
  ssh "${ssh_opts[@]}" michaelkang@$host true 2>/dev/null || host=100.122.37.52
  ssh "${ssh_opts[@]}" michaelkang@$host 'mkdir -p ~/Desktop/from-mbp' || return 1
  scp "${ssh_opts[@]}" "$src" "michaelkang@$host:$dest" >/dev/null || return 1
  print -rn -- "$dest" | pbcopy
  echo "sent ${src:t} → mini1"
  echo "path copied to clipboard: $dest"
}

# same as mini1send, for mini2 (tailscale IP only — no LAN fallback)
mini2send() {
  local src="$1" dest
  if [[ -z "$src" ]]; then
    src=$(print -rl -- ~/Desktop/*.(png|jpg|jpeg)(NDom) 2>/dev/null | head -1)
    [[ -z "$src" ]] && { echo "no image on ~/Desktop"; return 1; }
  fi
  [[ -f "$src" ]] || { echo "no such file: $src"; return 1; }
  # spaces break path detection when pasted (macOS shots also use U+202F), so flatten
  dest="/Users/josephjun/Desktop/from-mbp/${${src:t}//[^A-Za-z0-9._-]/_}"
  local ssh_opts=(-o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ConnectTimeout=5)
  local host=100.119.210.87
  ssh "${ssh_opts[@]}" josephjun@$host 'mkdir -p ~/Desktop/from-mbp' || return 1
  scp "${ssh_opts[@]}" "$src" "josephjun@$host:$dest" >/dev/null || return 1
  print -rn -- "$dest" | pbcopy
  echo "sent ${src:t} → mini2"
  echo "path copied to clipboard: $dest"
}

export EDITOR='nvim'

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
  # Pin fzf to Homebrew version so direnv/nix PATH changes don't cause version conflicts
  __fzfcmd() { echo "$BREW_PREFIX/bin/fzf" }
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

# OpenRouter key for the walkthrough-video TTS skill.
# Read from the git-ignored stack .env rather than hardcoded — this repo is pushed to GitHub.
__or_env="$HOME/Implentio/stack/main/packages/implentio-app/packages/api-v2/.env"
if [[ -f "$__or_env" ]]; then
  __or_line=$(grep -m1 '^OPENROUTER_API_KEY=' "$__or_env" 2>/dev/null)
  [[ -n "$__or_line" ]] && export "$__or_line"
fi
unset __or_env __or_line
