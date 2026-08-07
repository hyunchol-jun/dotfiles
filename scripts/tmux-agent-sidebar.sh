#!/usr/bin/env bash
# tmux-agent-sidebar: herdr-style sidebar pane listing every tmux pane that is
# running a Claude Code / codex agent — on this machine and on remote hosts —
# with live status from the pane title (spinner = busy) crossed with the hook-
# written state file (see .claude/agent-state.sh) that splits the non-busy ✳
# panes into "needs input" and "idle".
#
# Usage:
#   tmux-agent-sidebar.sh toggle    open/close the sidebar (one per tmux server)
#   tmux-agent-sidebar.sh sync [w]  move the open sidebar into window w (default:
#                                   the current one) — driven by tmux hooks so the
#                                   sidebar follows you across windows and sessions
#   tmux-agent-sidebar.sh run       the refresh loop the sidebar pane runs
#   tmux-agent-sidebar.sh --list    print agent panes on this machine (also piped over ssh)
#
# Keys (while the sidebar pane is focused):
#   ↑/↓ or j/k   move the highlight
#   Enter        jump to that pane — local panes get focused directly; remote
#                panes open (or refocus) a local "ssh:<host>" window that
#                attaches to the remote session with the pane selected
#   q            close the sidebar
#
# Config — tmux options (set in tmux.conf, reload with prefix+r), env vars as
# fallback when running outside tmux:
#   @agent_sidebar_hosts / AGENT_SIDEBAR_HOSTS   space-separated ssh hosts to poll
#   @agent_sidebar_width / AGENT_SIDEBAR_WIDTH   sidebar width in columns (default 44)
#
# The host list should name EVERY machine in the mesh: the local hostname is
# auto-skipped, so the identical dotfiles line works on all of them. Hosts are
# plain ssh destinations — aliases, users, ports, jump hosts from ~/.ssh/config
# all work. A new machine needs only: (1) its name added to the list,
# (2) passwordless ssh to it (ssh-copy-id <host>). Nothing is installed
# remotely; this script is piped over ssh, so remotes just need tmux + sshd.
# Unreachable or unauthenticated hosts show an error line instead of blocking.

set -u
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
export LC_ALL=en_US.UTF-8

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# tmux option first (survives config reloads; run-shell only sees the tmux
# server's stale env), then env var for non-tmux invocations.
HOSTS="$(tmux show -gqv @agent_sidebar_hosts 2>/dev/null)"
[ -n "$HOSTS" ] || HOSTS="${AGENT_SIDEBAR_HOSTS-}"
LOCAL_HOST="$(hostname -s)"
WIDTH="$(tmux show -gqv @agent_sidebar_width 2>/dev/null)"
[ -n "$WIDTH" ] || WIDTH="${AGENT_SIDEBAR_WIDTH:-44}"
TICK_SECS=2
REMOTE_EVERY=4                     # poll remotes every Nth tick (= every 8s)
CACHE_DIR="${TMPDIR:-/tmp}/agent-sidebar-$USER"

# ── agent discovery ──────────────────────────────────────────────────────────
# A pane counts as an agent pane when a claude/codex process is alive somewhere
# under its shell — pane titles alone lie (they stick around after the agent
# exits), so walk the process tree instead.
list_agents() {
  local panes
  # \r-joined because macOS awk rejects literal newlines in -v strings
  panes=$(tmux list-panes -a -F '#{pane_pid}|#{pane_id}|#{session_name}:#{window_index}.#{pane_index}|#{pane_title}' 2>/dev/null | tr '\n' '\r')
  [ -n "$panes" ] || return 0
  # Third output column: the pane's hook-written state (see .claude/agent-state.sh).
  # Read from THIS machine's home — over ssh --list runs remotely, so a remote
  # pane is matched against the remote host's own state dir.
  ps -Ao pid=,ppid=,comm= | awk -v panes="$panes" -v statedir="$HOME/.claude/.agent-state" '
    { parent[$1] = $2; comm[$1] = $3 }
    END {
      n = split(panes, L, "\r")
      for (i = 1; i <= n; i++) {
        line = L[i]
        p1 = index(line, "|"); rest = substr(line, p1 + 1)
        p2 = index(rest, "|"); rest2 = substr(rest, p2 + 1)
        p3 = index(rest2, "|")
        pid = substr(line, 1, p1 - 1)
        pane[pid] = substr(rest, 1, p2 - 1)
        tgt[pid] = substr(rest2, 1, p3 - 1)
        ttl[pid] = substr(rest2, p3 + 1)
        order[i] = pid
        ispane[pid] = 1
      }
      for (pid in comm) {
        if (comm[pid] ~ /(^|\/)(claude|codex)$/) {
          p = pid
          for (hops = 0; hops < 50 && (p in parent); hops++) {
            if (ispane[p]) { hit[p] = 1; break }
            p = parent[p]
          }
        }
      }
      for (i = 1; i <= n; i++) {
        pid = order[i]
        if (!hit[pid]) continue
        id = pane[pid]; sub(/^%/, "", id)
        state = ""
        f = statedir "/" id
        if ((getline state < f) <= 0) state = ""
        close(f)
        printf "%s\t%s\t%s\n", tgt[pid], ttl[pid], state
      }
    }'
}

# ── rendering ────────────────────────────────────────────────────────────────
C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BUSY=$'\033[36m'; C_WAIT=$'\033[1;33m'; C_ERR=$'\033[31m'
C_IDLE=$'\033[90m'; C_SEL=$'\033[7m'
# One entry per screen row; ROW_TGT is empty for headers/blanks (not selectable)
ROWS=(); ROW_HOST=(); ROW_TGT=()
N_BUSY=0; N_WAIT=0; N_IDLE=0
SEL=-1        # row index of the highlight, -1 when there are no agents
SEL_KEY=""    # "host|target" of the highlighted agent, to survive refreshes

add_row() {  # $1 = text, $2 = host, $3 = target ("" = not selectable)
  ROWS+=("$1"); ROW_HOST+=("${2-}"); ROW_TGT+=("${3-}")
}

append_section() {  # $1 = host label, stdin = "target<TAB>title<TAB>state" lines
  local label="$1" cols target title state first status avail line
  # pane width from tmux — tput honors an inherited COLUMNS env var and lies
  cols=$(tmux display -p -t "${TMUX_PANE:-}" '#{pane_width}' 2>/dev/null) || cols=$WIDTH
  [ -n "$cols" ] || cols=$WIDTH
  add_row "${C_DIM}── ${label} ──${C_RESET}" "" ""
  local any=0
  while IFS=$'\t' read -r target title state; do
    [ -n "$target" ] || continue
    any=1
    first="${title:0:1}"
    # Title wins over the state file: a spinner means busy no matter what the
    # last hook wrote. Self-heals the gap where approving a permission prompt
    # fires no hook, leaving a stale "input" file while the agent works.
    case "$first" in
      "✳") status=wait; title="${title:1}" ;;
      "✢"|"✶"|"✻"|"✽"|"·"|"∗"|"*"|[⠀-⣿]) status=busy; title="${title:1}" ;;
      *)   status=busy ;;
    esac
    [ "$status" = wait ] && [ "$state" != input ] && status=idle
    title="${title# }"
    avail=$(( cols - ${#target} - 4 )); [ "$avail" -lt 4 ] && avail=4
    title="${title:0:$avail}"
    case "$status" in
      wait) N_WAIT=$((N_WAIT + 1)); line="${C_WAIT}● ${target}${C_RESET} ${title}" ;;
      idle) N_IDLE=$((N_IDLE + 1)); line="${C_IDLE}● ${target}${C_RESET} ${C_DIM}${title}${C_RESET}" ;;
      *)    N_BUSY=$((N_BUSY + 1)); line="${C_BUSY}● ${target}${C_RESET} ${C_DIM}${title}${C_RESET}" ;;
    esac
    add_row "$line" "$label" "$target"
  done
  [ "$any" = 1 ] || add_row "${C_DIM}  (no agents)${C_RESET}" "" ""
  add_row "" "" ""
}

collect() {  # rebuild ROWS from local + cached remote data, keep the highlight
  ROWS=(); ROW_HOST=(); ROW_TGT=(); N_BUSY=0; N_WAIT=0; N_IDLE=0
  append_section "$LOCAL_HOST" < <(list_agents)
  local host
  for host in $HOSTS; do
    [ "$host" = "$LOCAL_HOST" ] && continue
    if [ -f "$CACHE_DIR/$host" ]; then
      if [ "$(head -1 "$CACHE_DIR/$host")" = "ERR" ]; then
        add_row "${C_DIM}── ${host} ──${C_RESET}" "" ""
        add_row "${C_ERR}  ✗ ssh failed${C_RESET} ${C_DIM}(ssh-copy-id ${host}?)${C_RESET}" "" ""
        add_row "" "" ""
      else
        append_section "$host" < "$CACHE_DIR/$host"
      fi
    else
      add_row "${C_DIM}── ${host} ──${C_RESET}" "" ""
      add_row "${C_DIM}  …connecting${C_RESET}" "" ""
      add_row "" "" ""
    fi
  done
  # Re-find the previously highlighted agent; fall back to the first one
  local i n=${#ROWS[@]}
  SEL=-1
  for ((i = 0; i < n; i++)); do
    [ -n "${ROW_TGT[i]}" ] || continue
    [ "$SEL" -lt 0 ] && SEL=$i
    if [ "${ROW_HOST[i]}|${ROW_TGT[i]}" = "$SEL_KEY" ]; then SEL=$i; break; fi
  done
  [ "$SEL" -ge 0 ] && SEL_KEY="${ROW_HOST[SEL]}|${ROW_TGT[SEL]}"
}

move_sel() {  # $1 = +1 / -1, wraps past the ends, skips headers/blanks
  local n=${#ROWS[@]} i=$SEL
  [ "$SEL" -ge 0 ] || return 0
  while :; do
    i=$(( (i + $1 + n) % n ))
    [ "$i" -eq "$SEL" ] && break
    if [ -n "${ROW_TGT[i]}" ]; then SEL=$i; break; fi
  done
  SEL_KEY="${ROW_HOST[SEL]}|${ROW_TGT[SEL]}"
}

render() {
  local out hdr line i n=${#ROWS[@]}
  printf -v hdr ' %s AGENTS %s  %s%d busy%s · %s%d input%s · %s%d idle%s' \
    "$C_DIM" "$C_RESET" "$C_BUSY" "$N_BUSY" "$C_RESET" "$C_WAIT" "$N_WAIT" "$C_RESET" \
    "$C_IDLE" "$N_IDLE" "$C_RESET"
  out="${hdr}"$'\033[K\n'" ${C_DIM}↑↓ move · ⏎ jump · q close${C_RESET}"$'\033[K\n\033[K\n'
  for ((i = 0; i < n; i++)); do
    line="${ROWS[i]}"
    if [ "$i" -eq "$SEL" ]; then
      # keep reverse video alive across the row's embedded color resets
      line="${line//"$C_RESET"/${C_RESET}${C_SEL}}"
      line="${C_SEL}${line}${C_RESET}"
    fi
    out+="${line}"$'\033[K\n'
  done
  printf '\033[H%s\033[J' "$out"
}

jump() {  # focus the highlighted agent's pane
  [ "$SEL" -ge 0 ] || return 0
  local host="${ROW_HOST[SEL]}" tgt="${ROW_TGT[SEL]}"
  local sess="${tgt%%:*}" win="${tgt%.*}" wid
  if [ "$host" = "$LOCAL_HOST" ]; then
    # One sequence: switching fires the follow hooks, and they must not land
    # between the window and the pane selection or the sidebar's move would
    # hand focus back to the wrong pane.
    tmux switch-client -t "$sess" \; select-window -t "$win" \; select-pane -t "$tgt" 2>/dev/null
  else
    # Point the remote session at the pane first, then attach — so a fresh
    # attach lands on it and an already-attached window snaps to it.
    ssh -o BatchMode=yes -o ConnectTimeout=3 "$host" \
      "tmux select-window -t '$win' \; select-pane -t '$tgt'" 2>/dev/null
    wid=$(tmux list-windows -F '#{window_id}|#{window_name}' 2>/dev/null |
      awk -F'|' -v n="ssh:$host" '$2 == n { print $1; exit }')
    if [ -n "$wid" ]; then
      tmux select-window -t "$wid"
    else
      tmux new-window -n "ssh:$host" "exec ssh -t '$host' tmux attach -t '$sess'"
    fi
  fi
}

fetch_remote() {  # background job: refresh one host's cache file
  local host="$1" out="$CACHE_DIR/$host"
  if ssh -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
      "$host" bash -s -- --list < "$SELF" > "$out.new" 2>/dev/null; then
    mv "$out.new" "$out"
  else
    printf 'ERR\n' > "$out"
    rm -f "$out.new"
  fi
}

run_loop() {
  mkdir -p "$CACHE_DIR"
  tmux set -p @agent_sidebar 1 2>/dev/null
  tmux select-pane -T agents 2>/dev/null
  printf '\033[?25l\033[2J'                 # hide cursor, clear once
  trap 'printf "\033[?25h"; exit 0' INT TERM EXIT
  local round=0 host key seq
  local last=$(( SECONDS - TICK_SECS ))    # force an immediate first refresh
  while :; do
    if (( SECONDS - last >= TICK_SECS )); then
      if (( round % REMOTE_EVERY == 0 )); then
        for host in $HOSTS; do
          [ "$host" = "$LOCAL_HOST" ] && continue
          # skip if the previous fetch for this host is still running
          [ -e "$CACHE_DIR/$host.new" ] || fetch_remote "$host" &
        done
      fi
      collect
      render
      last=$SECONDS
      round=$((round + 1))
    fi
    # Returns instantly on a keypress, times out (>128) otherwise; integer
    # timeouts only — /bin/bash on macOS is 3.2, which rejects fractions.
    if IFS= read -rsn1 -t 1 key; then
      case "$key" in
        "")      jump ;;                                # Enter
        j)       move_sel  1; render ;;
        k)       move_sel -1; render ;;
        q)       close_sidebar "${TMUX_PANE:-}"; exit 0 ;;   # restores the layout
        $'\033') IFS= read -rsn2 -t 1 seq || seq=""
                 case "$seq" in
                   '[A'|'OA') move_sel -1; render ;;
                   '[B'|'OB') move_sel  1; render ;;
                 esac ;;
      esac
    fi
  done
}

# There is at most one sidebar pane per tmux server, and it roams — so look for
# it everywhere, not just in the current window.
find_sidebar() {  # prints "<pane id> <window id>", empty when the sidebar is closed
  tmux list-panes -a -F '#{@agent_sidebar} #{pane_id} #{window_id}' 2>/dev/null |
    awk '$1 == 1 { print $2, $3; exit }'
}

# Opening the sidebar shrinks every existing pane proportionally, but killing it
# hands all the reclaimed columns back to the one pane beside it — an asymmetric
# round trip, so the neighbouring pane ratchets wider on every toggle. Stash the
# window layout on open and restore it on close to make the cycle lossless. The
# same two ends apply to a move: restore the window it leaves, stash the one it
# enters.
close_sidebar() {  # $1 = sidebar pane id
  local id="$1" win saved
  tmux set -gu @agent_sidebar_on 2>/dev/null       # stop `sync` chasing a dead pane
  win=$(tmux display -p -t "$id" '#{window_id}' 2>/dev/null)
  saved=$(tmux show -wqv -t "$win" @agent_sidebar_layout 2>/dev/null)
  tmux set -wu -t "$win" @agent_sidebar_layout 2>/dev/null
  # One command sequence: the restore is queued server-side before this pane —
  # and the tmux client issuing it, when called from the sidebar's own q key —
  # dies. select-layout fails harmlessly if panes came or went meanwhile.
  if [ -n "$saved" ]; then
    tmux kill-pane -t "$id" \; select-layout -t "$win" "$saved" 2>/dev/null
  else
    tmux kill-pane -t "$id" 2>/dev/null
  fi
}

toggle() {
  local id
  read -r id _ < <(find_sidebar)
  if [ -n "$id" ]; then
    close_sidebar "$id"                            # also clears @agent_sidebar_on
  else
    # Global, not per-window: `sync` reads it to follow the user around.
    tmux set -g @agent_sidebar_on 1 2>/dev/null
    tmux set -w @agent_sidebar_layout "$(tmux display -p '#{window_layout}')" 2>/dev/null
    # -f: span the full window height, not just the active pane's slice
    tmux split-window -fhb -l "$WIDTH" "exec '$SELF' run"
  fi
}

# Called from tmux hooks on every navigation event: while the sidebar is on,
# drag the one sidebar pane into the window the user just landed in. Moving it
# rather than kill + respawn keeps the refresh loop, the remote ssh caches and
# the highlight alive — a respawn would show "…connecting" for up to 8 seconds
# on every window switch.
sync() {  # $1 = fallback window, used only when no client is attached
  [ "$(tmux show -gqv @agent_sidebar_on 2>/dev/null)" = 1 ] || return 0
  mkdir -p "$CACHE_DIR" 2>/dev/null
  # Held windows switch faster than a move completes, and the move is a
  # read-modify-write spanning two windows — overlapping runs stash a layout
  # that already contains the sidebar, which then wrecks the restore on close.
  # Serialize them; a lock left behind by a killed sync is broken after ~2s.
  local lock="$CACHE_DIR/sync.lock" i
  for ((i = 0; i < 40; i++)); do
    mkdir "$lock" 2>/dev/null && break
    sleep 0.05
  done
  sync_move "${1:-}"
  rmdir "$lock" 2>/dev/null
}

sync_move() {  # $1 = fallback window; call with the sync lock held
  local win id="" from="" saved here active
  read -r id from < <(find_sidebar)
  [ -n "$id" ] || return 0                         # flag on but no pane: nothing to move
  # Where the user is *now*, not where the hook that queued us fired: by the
  # time we get the lock the window it named may be two switches stale. Also
  # the right answer for a detached `new-window -d`, which must not steal it.
  win=$(tmux display -p '#{window_id}' 2>/dev/null)
  [ -n "$win" ] || win="${1:-}"
  [ -n "$win" ] && [ "$from" != "$win" ] || return 0   # already here → also breaks hook recursion
  saved=$(tmux show -wqv -t "$from" @agent_sidebar_layout 2>/dev/null)
  # Read both of the target window's "before" facts in one round trip.
  IFS='|' read -r here active < <(tmux display -p -t "$win" '#{window_layout}|#{pane_id}')
  # One command sequence so no other hook interleaves mid-move. join-pane goes
  # first: if it fails (window too narrow) tmux drops the rest and the layout
  # bookkeeping stays consistent with where the pane actually is.
  local -a cmd
  cmd=(join-pane -fhb -l "$WIDTH" -s "$id" -t "$win"
       ';' set -wu -t "$from" @agent_sidebar_layout
       ';' set -w -t "$win" @agent_sidebar_layout "$here")
  [ -n "$saved" ] && cmd+=(';' select-layout -t "$from" "$saved")
  cmd+=(';' select-pane -t "$active")              # join-pane steals focus; hand it back
  tmux "${cmd[@]}" 2>/dev/null
}

case "${1:-run}" in
  --list) list_agents ;;
  toggle) toggle ;;
  sync)   sync "${2:-}" ;;
  run)    run_loop ;;
  *)      echo "usage: $0 [toggle|sync [window]|run|--list]" >&2; exit 1 ;;
esac
