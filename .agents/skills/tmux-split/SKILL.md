---
name: tmux-split
description: Open a tmux pane beside this agent session through the `tmux-split` CLI, which keeps windows at two panes. Use when asked to open or split a pane, or to run something (a server, a test watcher, an editor, a shell) where the user can see it next to you.
---

`tmux-split` is how panes are opened on this machine; use it in place of `tmux split-window`. It opens the pane next to your own (`$TMUX_PANE`) and holds every window at two panes: when your window is already full, it opens a sibling window right after it, named `<window>+`, and says so on stderr.

```sh
pane=$(tmux-split -d 'pnpm test --watch')
```

- **`-d`** is the agent default: the user's cursor stays in the pane they are typing in. Drop it only when the user asks to be taken to the new pane.
- **Direction:** side by side by default; `-v` for top/bottom.
- **The command** is one quoted string, typed into the new pane's shell, so the pane stays open after the command exits. Omit it for a plain shell.
- **`-c DIR`** sets the working directory; the default is your pane's current directory.
- **`-f`** forces a third pane. Use it only when the user asks for a third pane in this window.
- **stdout is the new pane's id** (such as `%42`) and nothing else.

Tell the user where the pane landed: beside you, or in the window `<window>+` when the cap redirected it.

Afterwards, read the pane with `tmux capture-pane -p -t "$pane"`, type into it with `tmux send-keys -t "$pane" "<text>" C-m`, and close it with `tmux kill-pane -t "$pane"`. Close only panes this session opened.
