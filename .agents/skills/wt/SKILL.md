---
name: wt
description: Create, open, list, remove or merge git worktrees through the `wt` CLI, which gives each worktree its own tmux window. Use whenever a task calls for a new worktree, for handing a task to a parallel agent on its own branch, or for cleaning up a finished worktree.
---

`wt` is the single way worktrees are made on this machine: it creates the worktree, seeds it from the main worktree (env files, direnv cache), and opens a tmux window the user can walk into. Use it in place of `git worktree add` / `remove`, which skip the seeding and the window. Run it from anywhere inside the repo; `wt` with no arguments prints the full usage.

## Hand a task to a parallel agent

```sh
target=$(wt new <branch> --layout agent --detach --prompt-file <file>)
```

- **`--layout agent --detach`** is the agent default: a single pane running the agent, created in the background so the user's focus stays where it is. Use the bare default (`pair`: editor beside agent, client switches to it) only when the user asks to work in the worktree themselves.
- **The prompt is the whole brief.** The new agent starts with an empty context, so write the goal, the relevant paths, the completion criterion, and what to report. Prefer `--prompt-file` for anything longer than a sentence; `--prompt "text"` is the short form.
- **stdout is the tmux target** (a window id such as `@12`) and nothing else; messages go to stderr. Tell the user the branch and window name so they can find it.
- **Watch it** with `tmux capture-pane -p -t "$target"`; steer it with `tmux send-keys -t "$target" "<text>" C-m`.

A new branch starts from the current `HEAD`; pass `--base origin/main` (or another ref) when the current checkout is not the right starting point.

## Exit codes

| Code | Meaning | What to do |
| --- | --- | --- |
| 3 | `wt new`: the branch already exists and is behind the default branch | Pick a new branch name. Pass `--reuse` only when the user wants that old branch. |
| 4 | `wt rm`: the worktree has uncommitted changes | Stop and ask the user. `--force` discards their work. |
| 5 | `wt rm --branch`: the worktree is gone, the unmerged branch was kept | Report it. Deleting it (`--branch-force`) is the user's call. |

If `wt new` reports that the worktree was created but its window was not, the worktree is fine: run `wt open <branch> --detach`. A `--prompt` is only delivered to a newly created window.

## Clean up

- `wt ls` lists branch, whether a window exists, and path.
- `wt rm <branch> --branch` removes the worktree, its windows and the merged branch.
- `wt merge <branch> [--strategy merge|rebase|squash]` merges into the default branch, then removes the worktree, branch and windows. A conflict aborts the merge and leaves everything intact. After a squash the branch is kept, because git cannot see it as merged.

Remove or merge only worktrees this session created, or ones the user named. `wt rm` and `wt merge` close the worktree's tmux windows, so when running inside that window, report your results before calling them: the command ends your own session.
