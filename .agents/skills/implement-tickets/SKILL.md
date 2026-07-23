---
name: implement-tickets
description: Drive a batch of /to-tickets ticket files to completion — work the frontier in dependency order, one /implement subagent per ticket, stacked on the current branch. Use when a .scratch/<slug>/issues/ directory of NN-slug.md tickets is ready to build.
---

# Implement Tickets

You are the **batch orchestrator**. Take a set of `/to-tickets` local ticket files, order them by
their blocking edges, and drive each one to completion by **spawning one subagent per ticket that
runs `/implement`**. The heavy work (TDD cycles, `/code-review-matt`, commits) happens inside each
subagent and is discarded on return — you keep only compact results. Keeping your own context light
is an explicit goal.

**The ticket files are the ledger.** Each ticket's `**Status:**` line is the source of truth:
`ready-for-agent` → `done` (or `blocked — <reason>`). A re-run of this skill is automatically a
resume: done tickets are skipped.

## Pre-flight

1. **Git repo with commits.** `git rev-parse --is-inside-work-tree` must print `true` and
   `git rev-parse --verify HEAD` must succeed. Otherwise stop and tell me.
2. **Not on the default branch, not detached.** `git branch --show-current` must name a branch that
   is not `main`/`master` (resolve the default via `git symbolic-ref --short refs/remotes/origin/HEAD`,
   falling back to whichever of main/master exists). On the default branch or detached HEAD → halt
   and tell me to switch to (or create) a working branch. All tickets stack **in place on the
   current branch**; never cut a new branch.
3. **Tree state.** `git status --porcelain`. If the only changes are the ticket files (and any spec
   they reference), commit them now as the first batch commit and say so. Any *other* dirty files →
   halt and ask me whether to stash, commit, or ignore them.

## Resolve the ticket set

The argument is a directory, glob, or explicit file paths.

- **Directory** (e.g. `.scratch/foo/issues`) → every `*.md` directly inside it.
- **Empty** → if exactly one `.scratch/*/issues/` directory exists, use it; zero or several → ask me
  which. Don't guess.

For each file, read it and extract:

- **Number/title** — from the `# <NN> — <Title>` heading (the `NN` filename prefix is the id).
- **Blocked by** — the `**Blocked by:**` line; resolve each referenced number/title to a ticket in
  the set. "None — can start immediately" → no blockers.
- **Status** — the `**Status:**` line. `done` → already complete, skip. Missing status line → treat
  as ready-for-agent.

A missing/empty file, a blocker referencing a ticket not in the set, or a dependency cycle → halt
and ask me (for a dangling blocker: is it already merged, or omitted by mistake?).

## Order and announce

Topologically sort by blocking edges; `NN` order breaks ties. Announce the plan in one pass — the
ordered list (id, title, blockers, current status) and the branch you'll stack on — then **start
without waiting for approval**. I'll interrupt if I disagree.

## Main loop — strictly sequential

Never run two subagents at once: they share one working tree. For each ticket in order:

1. **Status `done`?** Skip.
2. **Blocker not done?** (A blocker failed or was skipped earlier.) Do not start this ticket —
   record it as skipped-blocked and move on to the next ticket whose blockers are all done.
3. **Spawn one `general-purpose` subagent, synchronously** (`run_in_background: false`). Prompt it:

   > You are implementing one ticket of a stacked batch. Read the ticket file at `<path>` in full —
   > "What to build" is the end-to-end behaviour, the checkboxes are the acceptance criteria. Then
   > invoke the `implement` skill and follow it for exactly this ticket's scope: TDD at the seams,
   > typecheck and single test files regularly, full suite once at the end, then `code-review-matt`,
   > then commit to the current branch `<branch>` — you are on the feature branch the caller created
   > for this stacked work; implement in place, do NOT cut a new branch. In your final commit,
   > include the ticket file updated: tick each satisfied acceptance criterion and set
   > `**Status:** done`. Build nothing beyond this ticket's scope — later tickets cover the rest.
   > Return only: `{ status: done|blocked, commit: <sha>, criteria: <n>/<m> green, review: <one-line
   > code-review-matt outcome>, notes: <one line> }`. If you cannot get the full suite green or hit a
   > genuine decision only a human can make, commit nothing further, set the ticket's Status line to
   > `blocked — <reason>`, and return status blocked with the reason in notes.

4. **Handle the result.**
   - `done` → verify the ticket file now says `done` (fix it and amend/commit if the subagent
     forgot), record the compact result, continue.
   - `blocked` (or the subagent dies) → make sure the ticket's Status line records the blockage,
     relay the reason to me, and **pause the batch** — a later ticket may depend on it. Continue
     only on my direction; if the blocked attempt left commits on the branch, ask me before
     rewinding them.

Between tickets the tree is clean (each subagent commits its work), so each ticket stacks on the
previous one's HEAD.

## Final summary

When all tickets are done, skipped, or the batch is paused:

- Per-ticket status with each compact result (commit, criteria, review outcome).
- The branch name and `git log <first-batch-commit>^..HEAD --oneline`.
- What remains blocked/skipped and why.
- Nothing is pushed or opened as a PR unless I explicitly ask.
