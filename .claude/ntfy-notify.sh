#!/bin/bash
# Send Claude Code notifications to ntfy.sh for iPhone push notifications
# Topic is a secret URL - treat it like a password

NTFY_TOPIC="claude-hcjun-8447ba2be44b53d7"
DEDUP_DIR="$HOME/.claude/.ntfy-sent"

# Read the notification message from stdin (Claude Code hook passes it via stdin as JSON)
INPUT=$(cat)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null)
if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  MESSAGE="Claude Code needs your attention"
fi

# Deduplication: skip if the same exact message was already sent
mkdir -p "$DEDUP_DIR"
MSG_HASH=$(printf '%s' "$MESSAGE" | md5 -q 2>/dev/null || printf '%s' "$MESSAGE" | md5sum | cut -d' ' -f1)

# Clean up hashes older than 1 hour to prevent infinite accumulation
find "$DEDUP_DIR" -type f -mmin +60 -delete 2>/dev/null

if [ -f "$DEDUP_DIR/$MSG_HASH" ]; then
  exit 0
fi

curl -s \
  -H "Title: Claude Code" \
  -H "Tags: robot" \
  -d "$MESSAGE" \
  "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1

# Record that this message was sent
touch "$DEDUP_DIR/$MSG_HASH"
