# Codex computer use from tmux

Prompt Codex UI-testing sessions from tmux instead of the desktop app.
Works on any Mac where `./install` has run (minis and the MacBook).

How it works: `codex app-server` (kept alive by launchd) exposes the same
engine the desktop app uses; `codex --remote` attaches the terminal UI to it
over localhost. Computer use (screenshots, accessibility tree, clicks) is
available in these sessions — verified 2026-08-26 on mini1. It cannot
capture the ChatGPT/Codex app itself (self-capture safety block); every
other app works.

## Daily use

```
# in tmux (locally, or mini1/mini2 via mosh), new window (C-Space c), then:
cxr                # codex --remote ws://127.0.0.1:4500
```

Or from Claude Code: `/cxr <url> <what to test or do>` launches a session in
a detached tmux window and reports the findings.

## Setup per machine

`cd ~/dotfiles && git pull && ./install`

That's it: `scripts/codex-appserver-setup.sh` runs as a Dotbot shell step,
links the plist into `~/Library/LaunchAgents`, and bootstraps (or restarts)
the agent. It no-ops on machines without `~/.local/bin/codex`. Re-running `./install` after a plist edit
restarts the server with the new config.

Codex is expected at `~/.local/bin/codex` (the plist resolves it via
`$HOME`). If `bootstrap` rejects the symlink (some macOS versions do), copy
instead: `cp ~/dotfiles/launchd/com.codex.appserver.plist
~/Library/LaunchAgents/` and re-copy after editing the plist.

## Troubleshooting

- Server log: `/tmp/codex-appserver.log`
- Restart the server: `launchctl kickstart -k gui/$(id -u)/com.codex.appserver`
- Remove: `launchctl bootout gui/$(id -u)/com.codex.appserver` then delete
  the plist from `~/Library/LaunchAgents`.
