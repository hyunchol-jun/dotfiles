# Wispr Flow setup

Wispr Flow's config lives in `~/Library/Application Support/Wispr Flow/config.json`,
mixed with device/account state — do not symlink or check it in. Preferences
(dictionary, snippets, style, shortcuts) sync through the Wispr Flow account
(`cloudSync`), so most of this arrives by logging in. This note is the checklist
for anything that doesn't, plus the non-default settings worth knowing about.

## New machine

1. Install Wispr Flow and log in — cloud sync restores most preferences
2. Grant microphone + accessibility permissions when prompted (per-machine, never synced)
3. Verify the shortcuts below survived the sync; re-add any that didn't

## Non-default settings (as of Aug 2026)

### Shortcuts (Settings → any tab → Change shortcut)

| Action | Shortcut | Note |
| --- | --- | --- |
| Push to talk | Mouse 6 | hold to dictate |
| Hands-free mode | Double-tap Mouse 6, or Shift+Space | toggle start/stop |
| Join meeting / start Notetaker | **Opt+Shift+M** | moved off default Opt+M — it collided with the Alt+M window-maximize binding |
| Command Mode | fn, or Ctrl | select text, ask Flow |
| Paste last transcript | Ctrl+Cmd+V | |
| Copy last transcript | Ctrl+Cmd+C | |

### System (Settings → System)

- Launch app at login: on
- Show Flow Bar at all times: on
- Show app in dock: on

## Daily use

The main window is only a dashboard — close it (Cmd+W) freely; dictation keeps
working from the background process. Cmd+Q is what kills voice input.
