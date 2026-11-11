#!/usr/bin/env bash
# tmux-menu: tappable menus for clients without a real keyboard (iPad/Blink).
# Tapping the left end of the status bar opens the main menu; tapping the right
# end opens the session list (bindings in tmux.conf). Every row is a tap target,
# so nothing here needs the prefix key.
#
# Usage:
#   tmux-menu.sh <menu> <client> <pane>
#     main         sessions, then the actions below
#     sessions     just the session list
#     agents       every pane running Claude Code / codex, waiting ones first
#     windows      the windows of the current session
#     close-pane | close-window    yes/cancel confirmation
#   tmux-menu.sh statusbar    shorten window names in the status bar; run from
#                             tmux.conf after the theme has set its formats
#
# <client> and <pane> are filled in by the key binding (#{client_name} and
# #{pane_id}); the menus pass them along to each other.
#
# Kept bash 3.2-compatible: a tmux server started by mosh-server has a bare
# PATH, so this may run under /bin/bash.

set -u
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
export LC_ALL=en_US.UTF-8

DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$DIR/$(basename "$0")"
SIDEBAR="$DIR/tmux-agent-sidebar.sh"
SPLIT="$DIR/../bin/tmux-split"
TAB=$'\t'
NAME_MAX=24

# strip the branch-type prefix wt puts on window names, in tmux format syntax
SHORT_FMT='#{s/^(feat|fix|chore|refactor|docs|test)_//:window_name}'

esc()   { printf '%s' "${1//#/##}"; }   # menu labels are format-expanded by tmux
clip()  { local s=$1 n=$2; [ "${#s}" -le "$n" ] && printf '%s' "$s" || printf '%s…' "${s:0:$((n - 1))}"; }
short() { local s=$1; case $s in feat_*|fix_*|chore_*|refactor_*|docs_*|test_*) s=${s#*_} ;; esac; clip "$s" "$NAME_MAX"; }
again() { printf 'run-shell "%s %s %s %s"' "$SELF" "$1" "$CLIENT" "$PANE"; }

ARGS=()
item() { ARGS+=("$1" "${3:-}" "$2"); }   # item <label> <tmux command> [key]
sep()  { ARGS+=(""); }
note() { ARGS+=("-$1" "" ""); }          # a greyed-out, untappable row
# -M: handle the pointer even though the menu is opened through run-shell (tmux
# only does that by default for menus opened directly by a mouse binding).
#
# tmux has two pointer behaviours and neither suits both a finger and a mouse:
#   mouse (-O)     hovering highlights a row and a click picks it. A finger
#                  never hovers, so a tap would pick nothing.
#   touch (no -O)  touching a row highlights it and lifting picks it. Any
#                  mouse movement counts as a lift, so on a desktop the menu
#                  closes as soon as the mouse moves.
# So pick per client. A desktop terminal names itself (client_termtype, e.g.
# "ghostty 1.3.1"); Blink behind mosh reports nothing, which means touch.
# Override with `set -g @menu_mode touch|mouse` (default: auto).
# The bindings open the menu on MouseUp because in touch mode a lift outside
# the menu closes it.
pointer_flags() {
  local mode term
  mode=$(tmux show -gqv @menu_mode)
  if [ "$mode" != touch ] && [ "$mode" != mouse ]; then
    term=$(tmux display -p -c "$CLIENT" '#{client_termtype}' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case $term in ''|*blink*|*hterm*) mode=touch ;; *) mode=mouse ;; esac
  fi
  [ "$mode" = mouse ] && printf '%s' -O
}
show() {
  local flags=(-M); local o; o=$(pointer_flags); [ -z "$o" ] || flags+=("$o")
  tmux display-menu "${flags[@]}" -c "$CLIENT" -t "$PANE" -T "#[align=centre] $1 " -x "${2:-0}" -y S -- "${ARGS[@]}"
}

session_rows() {
  local id name wins cur mark n=0
  cur=$(tmux display -p -t "$PANE" '#{session_id}')
  while IFS=$TAB read -r id name wins; do
    n=$((n + 1)); [ "$n" -le 9 ] || break
    mark=' '; [ "$id" = "$cur" ] && mark='●'
    item "$mark $(esc "$name")  ($wins)" "switch-client -t '$id'" "$n"
  done < <(tmux list-sessions -F "#{session_id}$TAB#{session_name}$TAB#{session_windows}")
}

menu_main() {
  session_rows
  sep
  item 'Agents…'        "$(again agents)" a
  item 'Windows…'       "$(again windows)" w
  item 'Previous window' 'last-window' l
  sep
  item 'Split right'    "run-shell \"$SPLIT -h -t $PANE >/dev/null 2>&1\"" '|'
  item 'Split down'     "run-shell \"$SPLIT -v -t $PANE >/dev/null 2>&1\"" '-'
  item 'New window'     "new-window -c '#{pane_current_path}'" c
  item '#{?window_zoomed_flag,Unzoom pane,Zoom pane}' "resize-pane -Z -t $PANE" z
  item 'Agent sidebar'  "run-shell \"$SIDEBAR toggle\"" s
  sep
  item 'Close pane…'    "$(again close-pane)" x
  item 'Close window…'  "$(again close-window)" X
  show 'tmux'
}

menu_sessions() { session_rows; show 'Sessions' R; }

# Same classification as the sidebar: the pane title's first character says
# busy or not, and the hook-written state splits not-busy into input / idle.
menu_agents() {
  local target title state info wname pid first label waiting=() busy=() idle=()
  while IFS=$TAB read -r target title state; do
    [ -n "$target" ] || continue
    info=$(tmux display -p -t "$target" "#{pane_id}$TAB#{window_name}" 2>/dev/null) || continue
    pid=${info%%"$TAB"*}; wname=${info#*"$TAB"}
    first=${title:0:1}
    case $first in
      '✳'|'✢'|'✶'|'✻'|'✽'|'·'|'∗'|'*'|[⠀-⣿]) title=${title:1}; title=${title# } ;;
    esac
    label="$(esc "$(short "$wname")")  $(esc "$(clip "$title" 30)")"
    if [ "$first" != '✳' ]; then busy+=("~ $label$TAB$pid")
    elif [ "$state" = input ]; then waiting+=("! $label$TAB$pid")
    else idle+=("  $label$TAB$pid")
    fi
  done < <("$SIDEBAR" --list)
  local row n=0
  for row in ${waiting[@]+"${waiting[@]}"} ${busy[@]+"${busy[@]}"} ${idle[@]+"${idle[@]}"}; do
    n=$((n + 1)); [ "$n" -le 30 ] || break
    item "${row%%"$TAB"*}" "switch-client -t '${row#*"$TAB"}'"
  done
  [ "$n" -gt 0 ] || note 'No agents running'
  sep
  item '← Back' "$(again main)" b
  show 'Agents   ! needs you  ~ busy'
}

menu_windows() {
  local id idx name panes active mark n=0
  while IFS=$TAB read -r id idx name panes active; do
    n=$((n + 1)); [ "$n" -le 30 ] || break
    mark=' '; [ "$active" = 1 ] && mark='●'
    item "$mark $idx  $(esc "$(short "$name")")  ($panes)" "select-window -t '$id'"
  done < <(tmux list-windows -t "$PANE" -F "#{window_id}$TAB#{window_index}$TAB#{window_name}$TAB#{window_panes}$TAB#{window_active}")
  sep
  item '← Back' "$(again main)" b
  show 'Windows'
}

menu_close() {   # menu_close <pane|window>
  item "Yes, close this $1" "kill-$1 -t $PANE" y
  item 'Cancel' '' n
  show "Close this $1?"
}

statusbar() {
  local opt fmt new
  new="#{=/$NAME_MAX/…:$SHORT_FMT}"
  opt=window-status-format
  fmt=$(tmux show -gv "$opt")
  case $fmt in *'#W'*) tmux set -g "$opt" "${fmt//#W/$new}" ;; esac
}

if [ "${1:-}" = statusbar ]; then statusbar; exit; fi
MENU=${1:-main} CLIENT=${2:-} PANE=${3:-${TMUX_PANE:-}}
[ -n "$CLIENT" ] || CLIENT=$(tmux display -p '#{client_name}')
[ -n "$PANE" ] || PANE=$(tmux display -p '#{pane_id}')
case $MENU in
  main)         menu_main ;;
  sessions)     menu_sessions ;;
  agents)       menu_agents ;;
  windows)      menu_windows ;;
  close-pane)   menu_close pane ;;
  close-window) menu_close window ;;
  *) echo "usage: $0 [main|sessions|agents|windows|close-pane|close-window|statusbar] [client] [pane]" >&2; exit 1 ;;
esac
