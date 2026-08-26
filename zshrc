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
alias ccfh="claude --dangerously-skip-permissions --model fable --effort high"
alias ccfm="claude --dangerously-skip-permissions --model fable --effort medium"
alias ccox="claude --dangerously-skip-permissions --model opus --effort xhigh"
alias cx="codex --yolo"
alias oc="opencode"

# AWS SSO login without opening a browser: prints a URL + code to complete
# on any machine (open it in an incognito window to use different credentials).
# Same as the stack repo's `login` wrapper, plus --use-device-code.
aws-login-headless() {
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    # No profiles in the personal config → fall back to the stack repo's
    if ! grep -q '^\[profile ' "$config" 2>/dev/null; then
        config="$HOME/Implentio/stack/main/.aws/config"
    fi
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
    # The browser that opens the link decides the account: an existing AWS
    # session cookie silently completes the login as that user.
    echo ">>> Open the link below in a PRIVATE/incognito window (or a browser"
    echo ">>> profile signed in as this machine's AWS account), or you'll be"
    echo ">>> logged in as whatever account that browser already has a session for."
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

# attach to a remote box's tmux over tailscale.
# mosh survives IP changes, tailscale path flips (DERP<->direct), and wifi drops,
# and resumes on its own. its UDP rides inside the tailscale tunnel, so it also works
# on networks that block UDP outright. predict=adaptive stays quiet on a fast LAN
# and turns on local echo automatically once latency climbs (i.e. when working outside).
# `-i`/IdentitiesOnly are passed explicitly rather than relying on ~/.ssh/config,
# which is untracked — keeps these working on a fresh machine.
# NETWORK_TMOUT bounds orphaned mosh-servers (each one holds a tmux client) but is set
# to a week, not a day, so a box you haven't touched in a while still resumes. when the
# server does time out the tmux session itself survives untouched.
_remote_mosh() {  # $1 = short name (for errors), $2 = user@host
  mosh --ssh="ssh -o IdentitiesOnly=yes -i $HOME/.ssh/id_ed25519 -o ConnectTimeout=15" \
       --server="MOSH_SERVER_NETWORK_TMOUT=604800 /opt/homebrew/bin/mosh-server" \
       --predict=adaptive \
       "$2" -- /opt/homebrew/bin/tmux attach \
    || { echo "mosh to $1 failed — check tailscale is connected, or try ${1}ssh" >&2; return 1; }
}

# plain-ssh fallback for attaching, when mosh is unavailable. anything else mosh
# cannot do (scp, port forwarding) lives in the *send / *fwd helpers below.
_remote_ssh() {  # $1 = user@host
  ssh -t -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 \
      "$1" /opt/homebrew/bin/tmux attach
}

alias mini1='_remote_mosh mini1 michaelkang@100.122.37.52'
alias mini2='_remote_mosh mini2 josephjun@100.119.210.87'
alias mini1ssh='_remote_ssh michaelkang@100.122.37.52'
alias mini2ssh='_remote_ssh josephjun@100.119.210.87'

# Codex TUI attached to the local codex app-server (computer use works there,
# unlike a plain `codex` session). Run ON a mini, inside its tmux; the server
# is kept alive by launchd (~/dotfiles/launchd/com.codex.appserver.plist).
# --yolo matches cx/cc; append -m <model> or -c model_reasoning_effort=<level>
# per-invocation to override the config default.
alias cxr='codex --remote ws://127.0.0.1:4500 --yolo'

# forward ports from mini1 so its dev servers open in this machine's browser
# usage: mini1fwd [thisport:mini1port | port ...]   — ctrl-c to stop
#   default: 3000 3001 3002 (implentio-app ui / app-v3 / api-v2 — the browser
#   calls the api at localhost:3002, so Cognito login breaks without it)
#   mini1fwd 3000            → localhost:3000 here → mini1's 3000
#   mini1fwd 4000:3000 8080  → localhost:4000 here → mini1's 3000, plus 8080 → 8080
mini1fwd() {
  local specs=("$@") fwd=() local_p remote_p
  (( ${#specs[@]} )) || specs=(3000 3001 3002)
  for s in "${specs[@]}"; do
    local_p="${s%%:*}"; remote_p="${s##*:}"
    fwd+=(-L "${local_p}:localhost:${remote_p}")
    echo "http://localhost:${local_p} (this machine) → mini1:${remote_p}"
  done
  echo "(ctrl-c to stop)"
  ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 "${fwd[@]}" michaelkang@100.122.37.52 ||
    ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 "${fwd[@]}" michaelkang@100.122.37.52
}

# same as mini1fwd, for mini2
mini2fwd() {
  local specs=("$@") fwd=() local_p remote_p
  (( ${#specs[@]} )) || specs=(3000 3001 3002)
  for s in "${specs[@]}"; do
    local_p="${s%%:*}"; remote_p="${s##*:}"
    fwd+=(-L "${local_p}:localhost:${remote_p}")
    echo "http://localhost:${local_p} (this machine) → mini2:${remote_p}"
  done
  echo "(ctrl-c to stop)"
  ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 "${fwd[@]}" josephjun@100.119.210.87 ||
    ssh -N -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15 "${fwd[@]}" josephjun@100.119.210.87
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
  local ssh_opts=(-o IdentitiesOnly=yes -i ~/.ssh/id_ed25519
                  -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15)
  local host=100.122.37.52
  ssh "${ssh_opts[@]}" michaelkang@$host 'mkdir -p ~/Desktop/from-mbp' || return 1
  scp "${ssh_opts[@]}" "$src" "michaelkang@$host:$dest" >/dev/null || return 1
  print -rn -- "$dest" | pbcopy
  echo "sent ${src:t} → mini1"
  echo "path copied to clipboard: $dest"
}

# same as mini1send, for mini2
mini2send() {
  local src="$1" dest
  if [[ -z "$src" ]]; then
    src=$(print -rl -- ~/Desktop/*.(png|jpg|jpeg)(NDom) 2>/dev/null | head -1)
    [[ -z "$src" ]] && { echo "no image on ~/Desktop"; return 1; }
  fi
  [[ -f "$src" ]] || { echo "no such file: $src"; return 1; }
  # spaces break path detection when pasted (macOS shots also use U+202F), so flatten
  dest="/Users/josephjun/Desktop/from-mbp/${${src:t}//[^A-Za-z0-9._-]/_}"
  local ssh_opts=(-o IdentitiesOnly=yes -i ~/.ssh/id_ed25519
                  -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=15)
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
export PATH=$HOME/.opencode/bin:$PATH

# OpenRouter key for the walkthrough-video TTS skill.
# Read from the git-ignored stack .env rather than hardcoded — this repo is pushed to GitHub.
__or_env="$HOME/Implentio/stack/main/packages/implentio-app/packages/api-v2/.env"
if [[ -f "$__or_env" ]]; then
  __or_line=$(grep -m1 '^OPENROUTER_API_KEY=' "$__or_env" 2>/dev/null)
  [[ -n "$__or_line" ]] && export "$__or_line"
fi
unset __or_env __or_line
