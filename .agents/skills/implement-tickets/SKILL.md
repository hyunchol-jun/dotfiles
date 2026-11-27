---
name: implement-tickets
description: Drive a batch of /to-tickets ticket files to completion — work the frontier in dependency order, one subagent per ticket, stacked on the current branch. Use when a .scratch/<slug>/issues/ directory of NN-slug.md tickets is ready to build.
---

# Implement Tickets

You are the **batch orchestrator**. Take a set of `/to-tickets` local ticket files, order them by
their blocking edges, and drive each one to completion by **spawning one subagent per ticket**.
The heavy work (TDD cycles, `/code-review`, commits) happens inside each subagent and is discarded
on return — you keep only compact results. Keeping your own context light is an explicit goal.

**The ticket files are the ledger.** Each ticket's `**Status:**` line is the source of truth:
`ready-for-agent` → `done` (or `blocked — <reason>`). A re-run of this skill is automatically a
resume: done tickets are skipped. Ticket files live on disk only: `.scratch/` is git-ignored, so
status updates are edits in place and every commit holds code alone.

## Pre-flight

1. **Git repo with commits.** `git rev-parse --is-inside-work-tree` must print `true` and
   `git rev-parse --verify HEAD` must succeed. Otherwise stop and tell me.
2. **Not on the default branch, not detached.** `git branch --show-current` must name a branch that
   is not `main`/`master` (resolve the default via `git symbolic-ref --short refs/remotes/origin/HEAD`,
   falling back to whichever of main/master exists). On the default branch or detached HEAD → halt
   and tell me to switch to (or create) a working branch. All tickets stack **in place on the
   current branch**; never cut a new branch.
3. **Clean tree.** `git status --porcelain` must print nothing. Any dirty file → halt and ask me
   whether to stash, commit, or ignore it.
4. **Batch base.** Record `<base>` = `git merge-base HEAD <default-branch>`. Every commit in
   `<base>..HEAD` belongs to the batch, on a first run and on a resume alike.

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
   > "What to build" is the end-to-end behaviour, the checkboxes are the acceptance criteria. Build
   > exactly this ticket's scope: call the Skill tool with `tdd` at the seams, and run typecheck and
   > single test files regularly. Finish with lint, typecheck, and the **related tests**: the tests
   > your changed files reach (e.g. `jest --findRelatedTests <changed files>`, `vitest related
   > <changed files>`) plus every test file you added or edited. A ticket that changes the database
   > schema or migrations adds the package's full integration suite to its related tests. The
   > orchestrator runs the full suite once, after the last ticket. Then call the Skill tool with
   > `code-review` to review the work, then commit to the current branch `<branch>` — you are on the
   > feature branch the caller created for this stacked work; implement in place, do NOT cut a new
   > branch. The commit message stands on its own: it describes the change and its motivation, with
   > no ticket, spec, or plan references. After committing, update the ticket file on disk: tick
   > each satisfied acceptance criterion and set `**Status:** done`. The ticket file is git-ignored
   > and stays out of the commit. Build nothing beyond this ticket's scope — later tickets cover the
   > rest. Return only: `{ status: done|blocked, commit: <sha>, criteria: <n>/<m> green, review:
   > <one-line code-review outcome>, notes: <one line> }`. If you cannot get the related tests green
   > or hit a genuine decision only a human can make, commit nothing further, set the ticket's
   > Status line to `blocked — <reason>`, and return status blocked with the reason in notes.

4. **Handle the result.**
   - `done` → verify the ticket file now says `done` (edit it in place if the subagent forgot),
     record the compact result, continue.
   - `blocked` (or the subagent dies) → make sure the ticket's Status line records the blockage,
     relay the reason to me, and **pause the batch** — a later ticket may depend on it. Continue
     only on my direction; if the blocked attempt left commits on the branch, ask me before
     rewinding them.

Between tickets the tree is clean (each subagent commits its work), so each ticket stacks on the
previous one's HEAD.

## Final verification — full suite once

Per-ticket runs cover only related tests, so this is the batch's one full-suite run. Run it when the
main loop finishes; a paused batch runs it on the resume that finishes the loop.

1. **Find the touched packages** from `git diff --name-only <base>..HEAD`.
2. **Run each package's full suite** (its `test` script), output redirected to a log in your
   scratchpad. Read back only the summary lines and failing test names — keep your context light.
3. **Green** → record it for the summary. Done.
4. **Red** → attribute each failure to the batch commit that caused it: read the failure against
   `git log -p <base>..HEAD` for the code the failing test reaches. A failure no
   batch commit reaches is pre-existing or flaky: report it and leave it.
5. **Fix each culprit**, strictly sequentially, with one `general-purpose` subagent per culprit
   commit. Prompt it with the failing tests, the culprit commit sha, and its ticket path; it makes
   those tests green, runs the related tests, and commits a fix to `<branch>` whose message stands
   on its own (no ticket, spec, or plan references). It returns `{ status: done|blocked, commit,
   notes }`.
6. **Re-run the full suite.** The step is complete when every touched package's suite is green at
   HEAD apart from reported pre-existing failures. Still red after one fix round → stop and report
   the failures to me.

## Final summary

When all tickets are done, skipped, or the batch is paused:

- Per-ticket status with each compact result (commit, criteria, review outcome).
- The full-suite result: green, or what failed, which fix commits landed, and what was reported as
  pre-existing.
- The branch name and `git log <base>..HEAD --oneline`.
- What remains blocked/skipped and why.
- Nothing is pushed or opened as a PR unless I explicitly ask.
