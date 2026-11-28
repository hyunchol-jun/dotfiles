#!/usr/bin/env bash
# Apply the Hex (local dictation) setup kept in hex/: speech models, settings
# and vocabulary. Hex has no config file meant for linking: it rewrites its own
# settings.json, which also holds per-machine values such as the microphone, so
# this goes through the `hex` CLI instead.
# Run it once Hex has been opened and given its permissions. Safe to re-run;
# re-run it after editing anything in hex/.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEX_DIR="$DOTFILES_DIR/hex"
# English (transcribes while you talk) and Korean
MODELS=(parakeet_unified_en qwen3_asr06_b)

if ! command -v hex &>/dev/null; then
  echo "==> Hex is not installed; skipping"
  exit 0
fi

# Models download inside the running app, one at a time
hex start >/dev/null

installed() { hex model list | grep -E "^\*? +$1 " | grep -qv "not installed"; }

for model in "${MODELS[@]}"; do
  if installed "$model"; then
    echo "==> Hex model $model already installed"
    continue
  fi
  echo "==> Downloading Hex model $model..."
  hex model install "$model" >/dev/null
  for _ in $(seq 1 360); do
    installed "$model" && break
    sleep 5
  done
  installed "$model" || { echo "Hex model $model did not finish downloading"; exit 1; }
done

echo "==> Applying Hex settings..."
hex settings apply "$HEX_DIR/settings.json" >/dev/null
# Keyboard-language model switching is keyed by macOS input source ids
if [ "$(uname -s)" = Darwin ]; then
  hex settings apply "$HEX_DIR/settings.darwin.json" >/dev/null
fi

echo "==> Adding Hex vocabulary..."
jq -r '.[] | [.term, (.sounds_like | join(","))] | @tsv' "$HEX_DIR/vocabulary.json" |
  while IFS=$'\t' read -r term sounds_like; do
    if [ -n "$sounds_like" ]; then
      hex vocabulary add "$term" --sounds-like "$sounds_like" >/dev/null
    else
      hex vocabulary add "$term" >/dev/null
    fi
  done

echo "==> Hex ready: Option+Space starts and stops a dictation"
