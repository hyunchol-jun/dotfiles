#!/bin/sh
# Install + start the codex app-server launchd agent, minis only.
# Idempotent: safe to re-run on every `./install`.
# See docs/codex-remote-computer-use.md

case "$(hostname)" in
  mini1*|mini2*) ;;
  *) exit 0 ;;  # not a mini: the app-server should not run here
esac

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
