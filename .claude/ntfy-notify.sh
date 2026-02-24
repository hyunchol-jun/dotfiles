#!/bin/bash
# Send Claude Code notifications to ntfy.sh for iPhone push notifications
# Topic is a secret URL - treat it like a password

NTFY_TOPIC="claude-hcjun-8447ba2be44b53d7"

# Read the notification message from stdin (Claude Code hook passes it via stdin as JSON)
INPUT=$(cat)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null)
if [ -z "$MESSAGE" ] || [ "$MESSAGE" = "null" ]; then
  MESSAGE="Claude Code needs your attention"
fi

curl -s \
  -H "Title: Claude Code" \
  -H "Tags: robot" \
  -d "$MESSAGE" \
  "https://ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
