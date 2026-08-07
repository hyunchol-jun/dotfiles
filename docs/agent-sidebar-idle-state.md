# Plan: third "idle" state for the tmux agent sidebar

## Problem

The sidebar (`scripts/tmux-agent-sidebar.sh`) reads only the pane title, which
carries two states: spinner = busy, `✳` = everything else. So "waiting" lumps
together three different situations:

- agent stopped mid-task and **needs an answer** (permission prompt, question)
- agent **finished** its turn; output is sitting there for review
- agent is just **idle** at the prompt with nothing pending

The one that matters most — "needs an answer right now" — is indistinguishable
from the harmless two.

## Approach

Claude Code hooks fire on exactly the transitions we care about. A tiny hook
script records the latest event per tmux pane in a state file; the sidebar
reads those files to split `✳` into two states.

| Hook event         | Meaning                        | State written |
|--------------------|--------------------------------|---------------|
| `Notification`     | needs your input               | `input`       |
| `Stop`             | finished its turn              | `done`        |
| `UserPromptSubmit` | you engaged it again           | (file deleted)|

Final status shown per pane:

| Pane title | State file | Sidebar shows            |
|-----------|------------|---------------------------|
| spinner   | anything   | ● busy (cyan)             |
| `✳`       | `input`    | ● needs input (yellow)    |
| `✳`       | `done` / none | ● idle (dim gray)      |

Title always wins over a stale state file: if the title shows a spinner, the
pane is busy no matter what the file says. This self-heals the one gap in the
hook coverage — approving a permission prompt fires no hook, so the `input`
file lingers while the agent works; the spinner title masks it, and the next
`Stop` overwrites it with `done`.

## Pieces

### 1. State dir

`~/.claude/.agent-state/` — one file per pane, named after the pane id with
the `%` stripped (e.g. `44` for pane `%44`). File content: the state word.
Fixed path (not `$TMPDIR`) so the hook environment and the sidebar always
agree, on every machine.

### 2. New script: `.claude/agent-state.sh <state>`

~10 lines. Called by hooks with `input`, `done`, or `clear`:

- no `$TMUX_PANE` → exit 0 (Claude running outside tmux; sidebar can't see it anyway)
- `clear` → delete the pane's state file
- otherwise → write the state word to the pane's file
- housekeeping: delete state files older than 24 h (same pattern as the ntfy
  dedup dir) — panes close, files would otherwise pile up forever

### 3. Hook wiring: `.claude/settings.json`

Append to existing arrays — the current ntfy (`Notification`) and tts (`Stop`)
hooks stay untouched; Claude Code runs all hooks for an event:

- `Notification` → `bash ~/.claude/agent-state.sh input`
- `Stop`         → `bash ~/.claude/agent-state.sh done`
- `UserPromptSubmit` (new section) → `bash ~/.claude/agent-state.sh clear`

### 4. Sidebar changes: `scripts/tmux-agent-sidebar.sh`

- `list_agents`: add `#{pane_id}` to the tmux format, and append a third
  tab-separated column: the pane's state-file content (empty if no file).
  Remote panes need no extra work — `--list` runs on the remote machine and
  reads the remote's own state dir; the extra column rides through the
  existing ssh pipe and cache files.
- `append_section`: classify with the table above. New color for idle:
  dim gray dot. Yellow now means only "needs input".
- Header: `N busy · N input · N idle` (running counts for all three).

## Verification (during implementation)

1. `--list` prints the third column for a live agent pane.
2. Trigger a real permission prompt → dot turns yellow; approve it → cyan
   while working; let it finish → gray. Confirms the title/state precedence
   rules against real Claude Code behavior, including what the title actually
   shows during a permission prompt.
3. Old cache files from mini1 (two-column format) render without errors —
   the state column parses as empty until mini1 pulls the update.

## Known limits

- codex agents get no hooks, so their `✳` panes always show idle, never
  "needs input". Acceptable: primary use is Claude Code.
- A `Notification` for something informational (not a question) still shows
  yellow until the next turn. Rare; ignorable.
- mini1 must `git pull` to gain the hooks + new `--list` format; until then
  its section just lacks the idle/input split.

## Estimate

30–45 min including live verification. All changes in dotfiles:
`agent-state.sh` (new), `settings.json`, `tmux-agent-sidebar.sh`, this doc.

## Implemented — 2026-08-07

Built as planned, with two additions:

- **`SessionStart` (`startup|resume|clear`) also runs `agent-state.sh clear`.**
  tmux pane ids restart at `%0` when the tmux server restarts, so a stale file
  from a long-dead pane could be inherited by an unrelated new pane. Clearing
  on session start closes that window.
- **`install.conf.yaml`** gained the `~/.claude/agent-state.sh` symlink, so
  other machines get the hook script from `./install`.

Verified: `--list` emits the third column; all four classifications render with
the right color and counter (busy / input / idle / idle); two-column cache
files from a not-yet-updated host parse as empty state and render as idle.
Not yet exercised against a real permission prompt — that needs a live session
started after the settings change.
