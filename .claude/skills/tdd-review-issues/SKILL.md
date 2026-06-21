---
name: tdd-review-issues
description: Drive a set of /to-issues vertical-slice issues to completion by running /tdd-review-loop on each AFK issue in dependency order, stacking all work on one branch and pausing to hand HITL issues to the human. Use when you have a batch of issue files (e.g. issues/NN-slug.md produced by /to-issues) and want to implement them end-to-end with TDD + adversarial review.
---

You are the **batch orchestrator**. You own this whole run. Your job is to take a set of
`/to-issues`-style issue files, work out the order they must be built in, and drive each one to
completion through the `/tdd-review-loop` command — stacking all the work on a single branch and
handing the human-in-the-loop issues back to me to resolve.

You do **not** re-implement `/tdd-review-loop`. For each AFK issue you **run the `/tdd-review-loop`
command** with that issue's file path as its argument and let it run its full Phase 0–3 flow. Your
job is the layer *around* it: parsing the issue set, ordering by dependency, gating, the single
stacked branch, the progress ledger, and the final summary.

**This is an interactive skill.** `/tdd-review-loop` is itself interactive — it stops at gates
(acceptance-criteria approval, dirty tree, contested blockers, the 3-round cap, a red final gate).
This wrapper inherits that contract and adds its own gates (the run-plan approval, every HITL
issue, any per-issue failure). Across N issues that is N sets of `/tdd-review-loop` gates plus the
wrapper's — **that is by design, not a thing to engineer around.** If this skill is ever run with no
human present to answer, it must **halt at the first gate** rather than invent an autonomous default.
Do not push past a gate when no one is there to answer.

This skill does **not** query a remote issue tracker. It works off issue **files** (local `.md`)
that I pass as arguments.

---

## Pre-flight (do this first)

1. **Confirm a git repo with commits.** Run `git rev-parse --is-inside-work-tree` (treat anything
   other than the literal `true` as failure) and `git rev-parse --verify HEAD` (fails on a
   commit-less or bare repo). If either fails, stop and tell me — every later `git diff` and the
   stacked branch depend on it.

2. **Choose the orchestrator temp prefix `$WTMP` and load any prior ledger.** This prefix is
   **deliberately distinct** from `/tdd-review-loop`'s own `tdd-review-loop-<hash>` prefix so the two
   never collide:
   ```bash
   TOP=$(git rev-parse --show-toplevel) && [ -n "$TOP" ] || { echo "no work tree — aborting" >&2; exit 1; }
   WTMP=/tmp/tdd-review-issues-$(printf %s "$TOP" | shasum | cut -c1-12)   # bare assignment, no leading $
   ```
   The prefix is **deterministic and rediscoverable** (a hash of the repo toplevel), so a mid-run
   context summarization can't orphan the ledger — **if you lose `$WTMP`, recompute it exactly this
   way.** It is stable per checkout and distinct across separate worktrees, so concurrent batches in
   different trees don't clobber each other.

   **Do NOT blanket-`rm` `$WTMP-*` here** — unlike `/tdd-review-loop`, this skill's ledger is meant to
   **survive across invocations** so a re-run resumes. The ledger lives at `$WTMP-progress.md`. If it
   exists, read it; you'll reconcile it against the issue set below (Resumability).

3. **Do NOT delete or touch `/tdd-review-loop`'s `$TMP-*` files.** Each `/tdd-review-loop` invocation
   manages its own `tdd-review-loop-<hash>-*` state and clears it on its own pre-flight. Leave it alone.

---

## Parse arguments → the issue set

The argument is **one or more issue references** — usually local `.md` files:

- **A directory** (e.g. `issues/`) → every `*.md` file directly inside it.
- **A glob or several explicit paths** (e.g. `issues/02-*.md issues/03-*.md`) → exactly those files.
- **Empty** → default to `issues/` if it exists; otherwise **ask me** for the path(s). Don't guess.

For each resolved file:

1. **It must exist, be readable, and be non-empty.** A missing/unreadable/empty path → stop and ask
   me to correct it (name the bad path). Don't silently treat the path string as a requirement.
2. **Read it and extract:**
   - **Title** — the first `#` heading line.
   - **Type** — the `**Type**:` line: `HITL` or `AFK`. If absent or anything else, **ask me** how to
     classify that issue before proceeding (don't assume AFK).
   - **Blocked by** — parse the `## Blocked by` section for `#NN` references (and "None"/"can start
     immediately"). Map each `#NN` to the issue file whose name carries that `NN` prefix.

**Persist the parsed set** (path, title, type, blockers) to `$WTMP-set.md` so it survives a context
drop, then reconcile with the existing ledger (Resumability, below).

---

## Build the dependency DAG and order the run

1. **Topologically sort** the issues by their `Blocked by` edges. **`Blocked by` is authoritative**;
   the `NN` filename order is only a tie-breaker among issues with no ordering constraint between them
   (and a secondary tie-break is the order I passed them in).
2. **Cycle → stop.** If the blocked-by graph has a cycle, you cannot order it — report the cycle and
   stop.
3. **Dangling blocker.** If an issue is blocked by an `#NN` that is **not** in the provided set, don't
   silently ignore it — warn me and ask whether that blocker is already merged (treat as satisfied) or
   was omitted by mistake (stop so I can add it).

---

## Confirm the run plan (top-level gate)

Present the ordered execution list as a numbered plan. For each issue show: its `NN`/title, **Type**
(HITL/AFK), **blockers**, and its current ledger state (pending / done / paused). State the **single
stacked branch name** you'll use: `tdd-review-issues/<short-slug>` (slug from the issue set or the
parent plan; ask if ambiguous). Ask me:

- Is the order right?
- Are the HITL/AFK classifications right?
- Is the branch name right?

**Iterate until I approve.** Don't start implementing on your own interpretation of an edit.

---

## Set up the single stacked branch (once)

All issues stack on **one** branch — each issue builds on the commits of the ones before it.

1. **Dirty-tree check.** Run `git status --porcelain`. The issue files (and any plan docs they
   reference under `## Parent`) are commonly **untracked** — and an untracked tree would trip
   `/tdd-review-loop`'s own dirty-tree gate on **every** iteration. Resolve it **once, now**, by
   asking me which I want:
   - **Commit them to the branch** — add the issue files (and referenced plan docs) in a first commit
     so the tree is clean for every subsequent `/tdd-review-loop` run. (Default suggestion.)
   - **Record them as excluded paths** — capture them into a path list you will hand to *each*
     `/tdd-review-loop` run (its dirty-tree gate supports "record pre-existing paths to exclude"), so
     they're never attributed to any issue's diff.

   If the tree has *other* unrelated changes beyond the issue/plan files, **stop and ask me** how to
   handle them (stash / commit / exclude) — same discipline as `/tdd-review-loop`. Don't silently
   absorb them.
2. **Create and check out the stacked branch** `tdd-review-issues/<slug>` off the current default
   branch. If it already exists from a prior run, **resume on it** (don't recreate) — its commits are
   the prior issues' work. Persist the branch name to `$WTMP-branch` so it survives a context drop.

**Why per-run branching is suppressed:** when `/tdd-review-loop` reaches its own "branch off the
default/protected branch" pre-flight step, the current branch is the `tdd-review-issues/<slug>`
feature branch **this same agent just created this session** — which its gate explicitly allows it to
implement on **without** cutting a new `tdd-review-loop/<slug>` branch. That is what keeps everything
on one stack. Each `/tdd-review-loop` run then captures its own `$BASE = git rev-parse HEAD` at the
*current* (already-advanced) HEAD, so its diff scopes to **that issue only**, on top of the prior
issues' commits.

---

## Main loop — one issue at a time, in topological order

For each issue in order:

1. **Already DONE in the ledger?** Skip it (resume case).
2. **Blocker check.** Confirm every blocker is marked DONE in the ledger. By topological order they
   will be — *unless* a blocker was an unresolved HITL issue or a `/tdd-review-loop` run that
   failed/paused. **If any blocker is not DONE, do not start this issue** — pause the batch and tell me
   which blocker is outstanding.

3. **HITL issue → pause and hand to me.** Do **not** feed it to `/tdd-review-loop` (it's a TDD
   code-implementation loop; a decision/ADR issue with "no production code" has nothing to red-green).
   Instead: surface the issue's `## What to build` / decision list, tell me it needs human resolution,
   and **wait**. When I confirm it's resolved — including any of its own acceptance criteria about
   updating downstream issues — mark it DONE in the ledger and continue. If I say skip it, record it as
   SKIPPED and remember that its dependents are now blocked (step 2 will catch them).

4. **AFK issue → run `/tdd-review-loop`.** Run the **`/tdd-review-loop` command with the issue file
   path as its argument** (the path form — `/tdd-review-loop` reads the `.md` and treats its contents
   as the requirement). Drive its full interactive flow to completion, relaying every one of its gates
   to me:
   - Its **Phase 0** re-distills acceptance criteria. Tell it the issue **already has an
     `## Acceptance criteria` checklist** so it seeds Phase 0 from that rather than inventing one from
     scratch (it will still ask me to confirm — that's fine).
   - If I gave a global `--panel` / `--no-panel` preference for the batch, pass it through to each run;
     otherwise let `/tdd-review-loop` pick its mode by its own heuristic.
   - If you chose "record as excluded paths" above, hand that path list to the run so the issue/plan
     files stay out of its diff.
   - **On `STATUS: CONVERGED` + a green final gate** → the issue is done. Mark it DONE in the ledger.
   - **On any `/tdd-review-loop` escalation or failure** (stuck Phase 1, contested blocker, 3-round
     cap with open findings, red final gate) → it will escalate to me. **Pause the batch** at this
     issue — record it as PAUSED, do **not** auto-advance to the next issue (a later issue may depend
     on this one). Resume only when I direct.

5. **Record progress.** After each issue resolves, update `$WTMP-progress.md` (append-only ledger:
   issue path, final state DONE/SKIPPED/PAUSED, and a one-line note — e.g. AC summary or which gate it
   stopped at). Optionally tick the issue file's `## Acceptance criteria` checkboxes if I asked for it.

6. **Collect the self-test guide.** Each `/tdd-review-loop` run emits a disposable Phase-3 self-test
   guide and tells you its path. Record each path — you'll list them all at the end. Don't `git add`
   or commit these (they're disposable, per `/tdd-review-loop`'s own policy).

Between issues the tree is left clean by `/tdd-review-loop`'s own final gate, and HEAD has advanced —
so the next issue's run bases off the new HEAD and stacks on top.

---

## Resumability

The ledger `$WTMP-progress.md` **persists across invocations**. On a re-run:

- Reconcile the ledger against the freshly-parsed issue set. Issues marked **DONE** are skipped; the
  loop re-enters at the first **non-DONE** issue.
- If the issue **set has changed** since the ledger was written (files added/removed/reordered), point
  that out and re-confirm the run plan before resuming.
- Each `/tdd-review-loop` run additionally keeps its own `tdd-review-loop-<hash>-*` resume state, so a
  crash *inside* a single issue's run resumes there too.

---

## Final summary

When the loop finishes (all DONE, or paused/stopped at my direction), summarize for me:

- **Per-issue status** — DONE / HITL-resolved / SKIPPED / PAUSED, each with its acceptance-criteria
  outcome (from that issue's `/tdd-review-loop` run) and anything left contested or deferred.
- **The stacked branch** name and its commit range (`git log <default>..tdd-review-issues/<slug>
  --oneline`).
- **All Phase-3 self-test-guide paths** so I can verify each slice by hand.
- A reminder that — inheriting `/tdd-review-loop`'s policy — **nothing was pushed or opened as a PR**
  unless I explicitly asked.

**After any pause/escalation:** once I reply, act on my directive and **resume the loop from where you
stopped** — the run state is on disk under `$WTMP-*` (and each issue's own `$TMP-*`). If I say proceed,
continue with the next eligible issue; if I say stop, halt without advancing.

Throughout: stay in the repo's existing conventions, keep all work scoped to the issues, and do not
push or open a PR unless I ask.
