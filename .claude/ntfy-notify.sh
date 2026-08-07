#!/bin/bash
# Send Claude Code notifications to ntfy.sh for iPhone push notifications
# Topic is a secret URL - treat it like a password

NTFY_TOPIC="claude-hcjun-8447ba2be44b53d7"
DEDUP_DIR="$HOME/.claude/.ntfy-sent"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# Read the notification message from stdin (Claude Code hook passes it via stdin as JSON)
INPUT=$(cat)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null)
if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  MESSAGE="Claude Code needs your attention"
fi

# Title is a compact code "H.S folder": H = host (1 mbp, 2 mini1, 3 mini2),
# S = tmux session (0 personal, 1 implentio, 2 implentio-worktrees).
# e.g. "1.1 stack" = mbp, implentio session, stack folder. Unknown hosts or
# sessions fall back to their real name so nothing is ever mislabeled.
case "$(hostname -s)" in
  *[Mm]ac[Bb]ook*) TITLE="1" ;;
  mini1)           TITLE="2" ;;
  mini2)           TITLE="3" ;;
  *)               TITLE="$(hostname -s)" ;;
esac
if [ -n "${TMUX_PANE:-}" ]; then
  SESSION=$(tmux display -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
  case "$SESSION" in
    personal)            TITLE="$TITLE.0" ;;
    implentio)           TITLE="$TITLE.1" ;;
    implentio-worktrees) TITLE="$TITLE.2" ;;
    "")                  ;;
    *)                   TITLE="$TITLE.$SESSION" ;;
  esac
fi
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && TITLE="$TITLE ${CWD##*/}"

# Deduplication: skip if the same session already sent this exact message.
# Title is part of the hash so different sessions never suppress each other.
mkdir -p "$DEDUP_DIR"
MSG_HASH=$(printf '%s|%s' "$TITLE" "$MESSAGE" | md5 -q 2>/dev/null || printf '%s|%s' "$TITLE" "$MESSAGE" | md5sum | cut -d' ' -f1)

# Clean up hashes older than 1 hour to prevent infinite accumulation
find "$DEDUP_DIR" -type f -mmin +60 -delete 2>/dev/null

if [ -f "$DEDUP_DIR/$MSG_HASH" ]; then
  exit 0
fi

curl -s \
  -H "Title: $TITLE" \
  -H "Tags: robot" \
  -d "$MESSAGE" \
  "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1

# Record that this message was sent
touch "$DEDUP_DIR/$MSG_HASH"
