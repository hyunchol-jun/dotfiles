#!/bin/bash
# Claude Code Stop hook: speak the last assistant reply (OpenAI TTS, falling
# back to macOS `say`) and send it to Telegram as a voice message.
#
# Requires ~/.claude/telegram-tts.env (not in the dotfiles repo) with:
#   TELEGRAM_BOT_TOKEN=123456:ABC...
#   TELEGRAM_CHAT_ID=123456789
#   OPENAI_API_KEY=sk-...    # optional; without it notes use macOS say
#   TTS_VOICE=coral          # optional OpenAI voice, default coral
#   TTS_INSTRUCTIONS=...     # optional speaking-style prompt for OpenAI TTS
#   TTS_SPEED=1.15           # optional playback speed (both engines), default 1.0
#
# Voice notes are OFF by default. Enable selectively:
#   /tts on|off|once   - per-session toggle (writes ~/.claude/.tts-sessions/)
#   touch ~/.claude/tts-on - always on, all sessions

set -u

CONFIG="${TTS_CONFIG:-$HOME/.claude/telegram-tts.env}"
FLAG_DIR="$HOME/.claude/.tts-sessions"
GLOBAL_ON="$HOME/.claude/tts-on"
LOG="$HOME/.claude/tts-notify.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# The hook call re-runs itself in the background so Claude Code isn't blocked
# while say/ffmpeg/upload run.
if [ "${1:-}" != "--worker" ]; then
  INPUT=$(cat)
  printf '%s' "$INPUT" | nohup bash "$0" --worker >/dev/null 2>&1 &
  exit 0
fi

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

# Opt-in check: send only if this session (or everything) is enabled.
# Exit silently otherwise — this fires on every response in every session.
find "$FLAG_DIR" -type f -mtime +7 -delete 2>/dev/null
ENABLED=0
[ -f "$GLOBAL_ON" ] && ENABLED=1
[ -n "$SESSION_ID" ] && [ -f "$FLAG_DIR/$SESSION_ID" ] && ENABLED=1
if [ -n "$SESSION_ID" ] && [ -f "$FLAG_DIR/$SESSION_ID.once" ]; then
  ENABLED=1
  rm -f "$FLAG_DIR/$SESSION_ID.once"
fi
[ "$ENABLED" = 1 ] || exit 0

[ -f "$CONFIG" ] || { log "skip: no config file"; exit 0; }
# shellcheck source=/dev/null
source "$CONFIG"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { log "skip: config missing token or chat id"; exit 0; }

# The Stop hook input carries the final response text directly — no need to
# read the transcript file (whose text entries can flush minutes late).
TEXT=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
[ -n "$TEXT" ] || { log "skip: no last_assistant_message in hook input"; exit 0; }

# Make it listenable: drop code blocks, markdown syntax, and raw URLs
CLEAN=$(printf '%s\n' "$TEXT" \
  | awk '/^```/ { skip = !skip; next } !skip' \
  | sed -E 's/`([^`]*)`/\1/g; s/\*\*//g; s/__//g; s/^#+[[:space:]]*//; s~https?://[^[:space:])]+~ link ~g' \
  | tr -s '[:space:]' ' ')

# 4000 chars ~= 4.5 min of speech; also inside OpenAI TTS's 4096-char input
# limit. (The model also has a 2000-token cap — fine for English, but dense
# CJK text can exceed it; the say fallback covers that case.)
if [ ${#CLEAN} -gt 4000 ]; then
  CLEAN="${CLEAN:0:4000}. Message truncated."
fi
[ ${#CLEAN} -ge 10 ] || { log "skip: text too short after cleaning (${#CLEAN} chars)"; exit 0; }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TTS_VOICE="${TTS_VOICE:-coral}"
TTS_INSTRUCTIONS="${TTS_INSTRUCTIONS:-Calm, conversational tone. Read naturally.}"
ENGINE=""

# Both say and OpenAI output land well below typical voice-note loudness
# (~-14 LUFS), so normalize during the opus encode on both paths. atempo
# handles playback speed there too — gpt-4o-mini-tts ignores the API's
# `speed` param, and this works identically for both engines.
TTS_SPEED="${TTS_SPEED:-1.0}"
AFILTER="loudnorm=I=-14:TP=-1.5:LRA=11,atempo=$TTS_SPEED"

# OpenAI gpt-4o-mini-tts, opus output. Any failure (no key, network, quota,
# token limit) returns non-zero so the say fallback kicks in.
synth_openai() {
  [ -n "${OPENAI_API_KEY:-}" ] || return 1
  local payload http_code
  payload=$(jq -n --arg input "$CLEAN" --arg voice "$TTS_VOICE" --arg instructions "$TTS_INSTRUCTIONS" '{
    model: "gpt-4o-mini-tts",
    voice: $voice,
    input: $input,
    instructions: $instructions,
    response_format: "opus"
  }')
  http_code=$(curl -s --max-time 30 -o "$WORK_DIR/reply-raw.opus" -w '%{http_code}' \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "https://api.openai.com/v1/audio/speech") \
    || { log "openai: curl failed (network/timeout), falling back to say"; return 1; }
  if [ "$http_code" != 200 ]; then
    # On error the body is JSON, not audio — log it (token-limit errors show
    # up here) and discard so it can't be shipped to Telegram.
    log "openai: HTTP $http_code, falling back to say: $(tr -d '\n' < "$WORK_DIR/reply-raw.opus" | head -c 200)"
    return 1
  fi
  ffmpeg -loglevel error -y -i "$WORK_DIR/reply-raw.opus" \
    -af "$AFILTER" -c:a libopus -b:a 32k -ar 48000 "$WORK_DIR/reply.ogg" \
    || { log "openai: ffmpeg normalize failed, falling back to say"; return 1; }
  [ -s "$WORK_DIR/reply.ogg" ] || { log "openai: empty audio, falling back to say"; return 1; }
  ENGINE="openai/$TTS_VOICE"
}

# macOS say + ffmpeg re-mux (Telegram voice messages must be OGG/Opus)
synth_say() {
  local voice="Ava (Premium)"
  say -v '?' | grep -q '^Ava (Premium)' || voice="Samantha"
  printf '%s' "$CLEAN" > "$WORK_DIR/text.txt"
  say -v "$voice" -o "$WORK_DIR/reply.aiff" -f "$WORK_DIR/text.txt" \
    || { log "error: say failed (voice: $voice)"; return 1; }
  ffmpeg -loglevel error -y -i "$WORK_DIR/reply.aiff" \
    -af "$AFILTER" -c:a libopus -b:a 32k -ar 48000 "$WORK_DIR/reply.ogg" \
    || { log "error: ffmpeg conversion failed"; return 1; }
  ENGINE="say/$voice"
}

synth_openai || synth_say || exit 0

RESP=$(curl -s --max-time 60 \
  -F chat_id="$TELEGRAM_CHAT_ID" \
  -F voice=@"$WORK_DIR/reply.ogg" \
  "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendVoice")
if printf '%s' "$RESP" | jq -e '.ok' >/dev/null 2>&1; then
  log "sent: ${#CLEAN} chars via $ENGINE :: $(printf '%s' "$CLEAN" | head -c 60)"
else
  log "error: sendVoice failed: $(printf '%s' "$RESP" | head -c 300)"
fi
