#!/bin/bash
# Codex `notify` hook: forward to the ChatGPT desktop Computer Use client
# (preserving the previous notify config), then push to ntfy via the same
# script Claude Code uses. Codex passes a JSON payload as the last argument.

PAYLOAD="${@: -1}"

SKY="/Users/hyuncholjun/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
[ -x "$SKY" ] && "$SKY" turn-ended "$PAYLOAD" > /dev/null 2>&1

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

TYPE=$(printf '%s' "$PAYLOAD" | jq -r '.type // empty' 2>/dev/null)
[ "$TYPE" = "agent-turn-complete" ] || exit 0

MSG=$(printf '%s' "$PAYLOAD" | jq -r '."last-assistant-message" // ."last_assistant_message" // empty' 2>/dev/null)
[ -z "$MSG" ] && MSG="Codex finished its turn"
[ ${#MSG} -gt 140 ] && MSG="${MSG:0:140}…"

CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

jq -n --arg m "Codex: $MSG" --arg c "$CWD" '{message: $m, cwd: $c}' \
  | bash "$HOME/.claude/ntfy-notify.sh"
