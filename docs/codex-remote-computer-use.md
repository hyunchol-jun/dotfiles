# Codex computer use from tmux (mini1 / mini2)

Prompt Codex UI-testing sessions from the minis' tmux instead of screen
sharing into the desktop app.

How it works: `codex app-server` (kept alive by launchd) exposes the same
engine the desktop app uses; `codex --remote` attaches the terminal UI to it
over localhost. Computer use (screenshots, accessibility tree, clicks) is
available in these sessions — verified 2026-08-26 on mini1. It cannot
capture the ChatGPT/Codex app itself (self-capture safety block); every
other app works.

## Daily use

```
mini1              # mosh + tmux as usual
# new tmux window (C-Space c), then:
cxr                # codex --remote ws://127.0.0.1:4500
```

## One-time setup per mini

```
cd ~/dotfiles && git pull && ./install
which codex        # expect /opt/homebrew/bin/codex; if not, fix the path in the plist
ln -sf ~/dotfiles/launchd/com.codex.appserver.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.codex.appserver.plist
```

If `bootstrap` rejects the symlink (some macOS versions do), copy instead:
`cp ~/dotfiles/launchd/com.codex.appserver.plist ~/Library/LaunchAgents/`
and re-copy after editing the plist.

The plist is deliberately NOT in install.conf.yaml — launchd auto-starts
anything in `~/Library/LaunchAgents` at login, and the server should run
only on the minis, not on every machine that runs Dotbot.

## Troubleshooting

- Server log: `/tmp/codex-appserver.log`
- Restart the server: `launchctl kickstart -k gui/$(id -u)/com.codex.appserver`
- Remove: `launchctl bootout gui/$(id -u)/com.codex.appserver` then delete
  the plist from `~/Library/LaunchAgents`.
