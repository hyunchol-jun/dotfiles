# Plan: sidebar toggle state survives session/window navigation

## Problem

The sidebar's "open" state lives in the pane itself: `run_loop` stamps the
pane with a `@agent_sidebar` pane option (`scripts/tmux-agent-sidebar.sh`,
`run_loop`), and `toggle()` only looks for that pane in the **current window**.
So the sidebar is glued to whichever window it was opened in — switch to
another window or session and it stays behind. You have to toggle it again
(and again) as you move around.

Desired behavior: toggle once → the sidebar follows you across windows and
sessions until you toggle it off.

## Approach

Make "sidebar on" a **global** flag, and re-sync the sidebar's location on
every navigation event via tmux hooks.

1. **Global flag** — `toggle` sets/unsets `@agent_sidebar_on` as a global
   option (`tmux set -g`), instead of only acting on the current window.
2. **Hooks** — in `tmux.conf`:
   - `set-hook -g client-session-changed 'run-shell ".../tmux-agent-sidebar.sh sync"'`
   - `set-hook -g after-select-window    'run-shell ".../tmux-agent-sidebar.sh sync"'`
3. **New `sync` subcommand** — checks the flag; if on and the current window
   has no sidebar pane, **move** the existing sidebar pane here with
   `join-pane -fhb -l $WIDTH` rather than kill + respawn.

Moving (not respawning) matters: it keeps the refresh loop, the remote ssh
caches, and the highlight position alive. A respawn would show "…connecting"
for up to 8 seconds on every window switch.

## Edge cases to handle

- **Layout stash bookkeeping.** The current open/close cycle stashes
  `@agent_sidebar_layout` per window so closing restores pane sizes
  (`close_sidebar` / `toggle`). With a moving pane, `sync` must do both ends
  of the move: restore the layout of the window it leaves, stash the layout
  of the window it enters. Same code, run twice.
- **Hook recursion.** `join-pane` can itself fire `after-select-window`.
  The "sidebar already in this window → do nothing" check in `sync` breaks
  the loop; add an explicit guard only if that proves insufficient.
- **Focus.** After `join-pane` the sidebar pane may end up focused; `sync`
  must re-select the pane the user was on.

## Known limitation

tmux global options are shared across clients. With two clients attached to
different sessions, the sidebar can only exist in one place — it follows
whichever client navigated last. Single-client use (the normal case) is
unaffected.

## Size

~30 lines in `scripts/tmux-agent-sidebar.sh` (the `sync` subcommand + flag
handling in `toggle`) plus 2 hook lines in `tmux.conf`.

## As built

Implemented as planned, with three deviations found while testing:

1. **Three hooks, not two.** `after-new-window` was added — creating a window
   with prefix+c is navigation too, and without it the sidebar stays behind.
   Each hook is wrapped in `if -F '#{@agent_sidebar_on}' { … }` so no process
   is spawned at all while the sidebar is closed. The command has to be written
   inline in every hook: a `run-shell` string stored in a user option is *not*
   format-expanded when referenced as `#{@option}`, so the indirection silently
   does nothing.
2. **`sync` is serialized by a lock.** Holding down a window-switch key fires
   syncs faster than a move completes. Their read-modify-write cycles interleave
   and one of them stashes a layout that already contains the sidebar — which
   then wrecks the layout restore on close (panes come back at the sidebar's
   width). `sync` now takes a mkdir lock in the cache dir; a lock orphaned by a
   killed sync is broken after ~2s.
3. **`sync` re-reads the target window after taking the lock**, rather than
   trusting the `#{window_id}` the hook passed it. By then that window can be
   two switches stale. Reading the client's current window makes queued syncs
   converge on where the user actually is, and makes a detached `new-window -d`
   correctly *not* steal the sidebar. The hook's argument survives only as a
   fallback for when no client is attached.

`jump` now issues its switch-client/select-window/select-pane as one tmux
command sequence, so a follow hook cannot fire between the window and the pane
selection and hand focus back to the wrong pane.

A move takes ~40ms, off the client's critical path (`run-shell -b`).
