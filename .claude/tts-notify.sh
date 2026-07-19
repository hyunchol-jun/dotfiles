#!/bin/bash
# Claude Code Stop hook: speak the last assistant reply with macOS TTS and
# send it to Telegram as a voice message.
#
# Requires ~/.claude/telegram-tts.env (not in the dotfiles repo) with:
#   TELEGRAM_BOT_TOKEN=123456:ABC...
#   TELEGRAM_CHAT_ID=123456789
#
# Disable without editing settings: touch ~/.claude/tts-off

set -u

CONFIG="$HOME/.claude/telegram-tts.env"
OFF_SWITCH="$HOME/.claude/tts-off"
LOG="$HOME/.claude/tts-notify.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# The hook call re-runs itself in the background so Claude Code isn't blocked
# while say/ffmpeg/upload run.
if [ "${1:-}" != "--worker" ]; then
  INPUT=$(cat)
  printf '%s' "$INPUT" | nohup bash "$0" --worker >/dev/null 2>&1 &
  exit 0
fi

[ -f "$OFF_SWITCH" ] && { log "skip: tts-off switch present"; exit 0; }
[ -f "$CONFIG" ] || { log "skip: no config file"; exit 0; }
# shellcheck source=/dev/null
source "$CONFIG"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { log "skip: config missing token or chat id"; exit 0; }

INPUT=$(cat)

# The Stop hook input carries the final response text directly — no need to
# read the transcript file (whose text entries can flush minutes late).
TEXT=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$TEXT" ] || { log "skip: no last_assistant_message in hook input"; exit 0; }

# Make it listenable: drop code blocks, markdown syntax, and raw URLs
CLEAN=$(printf '%s\n' "$TEXT" \
  | awk '/^```/ { skip = !skip; next } !skip' \
  | sed -E 's/`([^`]*)`/\1/g; s/\*\*//g; s/__//g; s/^#+[[:space:]]*//; s~https?://[^[:space:])]+~ link ~g' \
  | tr -s '[:space:]' ' ')

if [ ${#CLEAN} -gt 1500 ]; then
  CLEAN="${CLEAN:0:1500}. Message truncated."
fi
[ ${#CLEAN} -ge 10 ] || { log "skip: text too short after cleaning (${#CLEAN} chars)"; exit 0; }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

VOICE="Ava (Premium)"
say -v '?' | grep -q '^Ava (Premium)' || VOICE="Samantha"

printf '%s' "$CLEAN" > "$WORK_DIR/text.txt"
say -v "$VOICE" -o "$WORK_DIR/reply.aiff" -f "$WORK_DIR/text.txt" \
  || { log "error: say failed (voice: $VOICE)"; exit 0; }

# Telegram voice messages must be OGG/Opus
ffmpeg -loglevel error -y -i "$WORK_DIR/reply.aiff" \
  -c:a libopus -b:a 32k -ar 48000 "$WORK_DIR/reply.ogg" \
  || { log "error: ffmpeg conversion failed"; exit 0; }

RESP=$(curl -s --max-time 60 \
  -F chat_id="$TELEGRAM_CHAT_ID" \
  -F voice=@"$WORK_DIR/reply.ogg" \
  "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendVoice")
if printf '%s' "$RESP" | jq -e '.ok' >/dev/null 2>&1; then
  log "sent: ${#CLEAN} chars, voice $VOICE :: $(printf '%s' "$CLEAN" | head -c 60)"
else
  log "error: sendVoice failed: $(printf '%s' "$RESP" | head -c 300)"
fi
