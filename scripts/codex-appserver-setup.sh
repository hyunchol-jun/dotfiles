#!/bin/sh
# Install + start the codex app-server launchd agent.
# Idempotent: safe to re-run on every `./install`.
# See docs/codex-remote-computer-use.md

# Skip machines without codex installed (plist expects it at ~/.local/bin/codex)
[ -x "$HOME/.local/bin/codex" ] || exit 0

PLIST_SRC="$HOME/dotfiles/launchd/com.codex.appserver.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.codex.appserver.plist"
LABEL="com.codex.appserver"

mkdir -p "$HOME/Library/LaunchAgents"
ln -sf "$PLIST_SRC" "$PLIST_DST"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  # already loaded; kickstart so a plist edit takes effect
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
else
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
fi
echo "codex app-server agent active"
