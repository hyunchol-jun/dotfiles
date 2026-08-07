#!/bin/bash
# agent-state: record what a Claude Code pane is waiting on, for the tmux
# agent sidebar. The pane title only distinguishes busy from not-busy; these
# hook-driven state files split not-busy into "needs input" vs "idle".
#
# Called from .claude/settings.json hooks:
#   Notification     -> agent-state.sh input   (agent is asking something)
#   Stop             -> agent-state.sh done    (turn finished)
#   UserPromptSubmit -> agent-state.sh clear   (you engaged it again)
#
# One file per tmux pane, named after the pane id with the % stripped
# (pane %44 -> file "44"). Fixed path so hooks and sidebar always agree.

STATE_DIR="$HOME/.claude/.agent-state"

# Not in tmux: the sidebar can't see this session at all, so nothing to record.
[ -n "${TMUX_PANE:-}" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Panes close without notice; drop anything a day old so files don't pile up.
find "$STATE_DIR" -type f -mmin +1440 -delete 2>/dev/null

FILE="$STATE_DIR/${TMUX_PANE#%}"
case "${1:-}" in
  clear) rm -f "$FILE" ;;
  input|done) printf '%s\n' "$1" > "$FILE" ;;
esac
exit 0
