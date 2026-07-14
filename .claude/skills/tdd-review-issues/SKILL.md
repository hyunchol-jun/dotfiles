---
name: tdd-review-issues
description: Drive a batch of /to-issues issue files to completion — one /tdd-review-loop subagent per AFK issue, in dependency order, stacked on one branch. Use when you have a batch of issue files (e.g. issues/NN-slug.md) to implement end-to-end.
---

You are the **batch orchestrator**. You own this whole run. Your job is to take a set of
`/to-issues`-style issue files, work out the order they must be built in, and drive each one to
completion — stacking all the work on a single branch, **delegating each AFK issue to a
`/tdd-review-loop` subagent**, and handing the human-in-the-loop issues back to me to resolve.

You do **not** re-implement `/tdd-review-loop`. For each AFK issue you **spawn a `general-purpose`
subagent that runs `/tdd-review-loop --afk` with that issue's file path** and let it run its full
Phase 0–3 flow inside its own context; it returns only a compact structured result. Your job is the
thin layer *around* it: parsing the issue set, ordering by dependency, gating, the single stacked
branch, the progress ledger, and the final summary. **Keeping your own context light is an explicit
goal** — the heavy per-issue work (the loop's body, every red-green cycle, the review rounds) lives
in the subagent and is discarded on return; you retain only the small result objects and the on-disk
ledger, so a long batch can't rot your context.

This skill does **not** query a remote issue tracker. It works off issue **files** (local `.md`)
that I pass as arguments.

## Vocabulary — three moves, keep them distinct

- **Halt** — one of *your own* pre-loop stops, before any issue is running: dirty tree beyond the
  issue files, detached HEAD, on the default branch, a dependency cycle, a dangling blocker, an
  ambiguous `**Type**`. Stop and wait for me. **A halt writes no ledger row.**
- **Pause** — an issue-level stop, recorded in the ledger as `PAUSED`: a HITL issue awaiting my
  resolution, or an AFK subagent that returned `state: BLOCKED` (or died). The batch does not
  advance past an unresolved pause that a later issue depends on.
- **Rewind-and-respawn** — the only way a PAUSED AFK issue continues. A `/tdd-review-loop` run never
  resumes across re-spawns (its pre-flight wipes its own `tdd-review-loop-<hash>-*` state; those
  `$TMP-*` files only bridge a context summarization *within* a run). Once I direct you to resume:
  **rewind the branch back to `$BASE`** (`git reset --hard $BASE`, discarding the paused run's
  partial commits), then spawn a fresh subagent — it re-reads its criteria from the issue and
  rebuilds on a clean base with an honest diff.

**Ledger states are only `DONE` / `SKIPPED` / `PAUSED` — "BLOCKED" is never written to the ledger.**
"BLOCKED" appears in exactly two places, both on the subagent's result object: `state: BLOCKED`,
which you record as a **`PAUSED`** row, and `blocked_reason`, the loop's `BLOCKED:{reason, detail}`
payload string, which you relay to me verbatim.

## Autonomy — a two-tier handoff

- **AFK issues run autonomously in a subagent.** `/tdd-review-loop --afk` proceeds from the
  documentation (the issue's `## Acceptance criteria`, `## What to build`, and the `## Parent` plan
  doc) and reaches a human only by **returning `state: BLOCKED`** for a genuine blocker — the loop
  defines those; you don't second-guess them. You record that issue `PAUSED` and relay it to me.
- **HITL issues and your own halts stay in-thread.** A HITL issue pauses for me to resolve (it has
  no code to TDD). Your halts also surface to me. Everything else you **decide from the issue files
  and announce-and-proceed** (run order, branch name, committing the issue/plan files), rather than
  asking.

So across a batch you reach me only: once up front (if something structural is ambiguous), at **each
HITL issue** as it's reached, and otherwise only when a subagent returns `BLOCKED`. There is **no
per-gate relay** for AFK work — that is the point. (If I explicitly ask to drive a particular issue
by hand, run that one issue **in-thread** with `/tdd-review-loop --interactive` instead of
delegating it to a subagent — a `--interactive` subagent would block on a prompt no one can answer.)

**One upfront checkpoint is usually unavoidable:** if issue 01 is HITL and blocks the rest (the
common `/to-issues` shape), the run opens by pausing for me to resolve 01, then proceeds
autonomously through the AFK chain.

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

   **`$WTMP` (and `$TOP`, and the per-issue `$BASE` below) are NOT persistent shell variables across
   tool calls** — each Bash invocation is a fresh shell, so an assignment in one call is gone by the
   next. Either recompute the value inline at the top of every Bash command that needs it, or do the
   assignment and its use **within a single command**. Never write `$WTMP-set.md` in a later, separate
   Bash call assuming the earlier assignment survived — it won't, and you'll silently write to
   `-set.md` in the cwd.

   **Do NOT blanket-`rm` `$WTMP-*` here** — unlike `/tdd-review-loop`, this skill's ledger is meant to
   **survive across invocations** so a re-run resumes. The ledger lives at `$WTMP-progress.md`.
   **If it exists, this run is a resume — read `resume.md` (in this skill's folder) now and follow
   it alongside the sections below.**

3. **Do NOT delete or touch `/tdd-review-loop`'s `$TMP-*` files.** Each `/tdd-review-loop` invocation
   manages its own `tdd-review-loop-<hash>-*` state and clears it on its own pre-flight. Leave it alone.

---

## Parse arguments → the issue set

The argument is **one or more issue references** — usually local `.md` files — optionally preceded or
followed by a single flag that sets the review-panel mode for each loop run (`--panel` / `--no-panel`):

- **Batch panel flag (optional).** Detect a `--panel` or `--no-panel` token **only when the whole
  first or last whitespace-delimited token equals it** (ASCII-literal, case-sensitive — a mid-text or
  partial token like `--panel-feature.md` is an issue reference, not a flag). If present, **strip that
  token** from the argument before resolving issue references, and **persist the literal token to
  `$WTMP-panel-pref`**. If **no** flag is present **on a fresh run** (no existing `$WTMP-progress.md`
  ledger), `rm -f "$WTMP-panel-pref"` so a stale preference from a prior run can't linger — its absence
  means "no batch preference," and each loop run picks its own mode by heuristic. (On a resume,
  `resume.md` governs the persisted preference.) This is the *only* way a batch panel preference is
  set. (There is no batch `--interactive` flag — to hand-drive a single issue, see the in-thread
  `--interactive` exception above.)
- **A directory** (e.g. `issues/`) → every `*.md` file directly inside it.
- **A glob or several explicit paths** (e.g. `issues/02-*.md issues/03-*.md`) → exactly those files.
- **Empty** (after stripping any flag) → default to `issues/` if it exists; otherwise **ask me** for
  the path(s). Don't guess.

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
drop, then — on a resume — reconcile with the existing ledger per `resume.md`.

---

## Build the dependency DAG and order the run

1. **Topologically sort** the issues by their `Blocked by` edges. **`Blocked by` is authoritative**;
   the `NN` filename order is only a tie-breaker among issues with no ordering constraint between them
   (and a secondary tie-break is the order I passed them in).
2. **Cycle → halt.** If the blocked-by graph has a cycle, you cannot order it — report the cycle and
   stop.
3. **Dangling blocker → halt.** If an issue is blocked by an `#NN` that is **not** in the provided
   set, don't silently ignore it — warn me and ask whether that blocker is already merged (treat as
   satisfied) or was omitted by mistake (stop so I can add it).

---

## Announce the run plan (proceed unless structurally ambiguous)

Present the ordered execution list as a numbered plan. For each issue show: its `NN`/title, **Type**
(HITL/AFK), **blockers**, and its current ledger state (pending / done / skipped / paused). State the **single
stacked branch** you'll build on: the branch you're **currently on** (`git branch --show-current`) —
this skill stacks all the work in place and does **not** cut a new branch. **Announce the plan and
proceed** — give the order, the HITL/AFK classification per issue, and the branch name in one pass,
then start; you don't need my approval to begin. Halt **only** when something is structurally
ambiguous: a dependency cycle, an issue whose `**Type**` is missing or is neither `HITL` nor `AFK`, a
dangling blocker (the DAG section above), or a current branch that can't be stacked on — a detached
HEAD, or the default/protected branch (the branch-setup section handles both). I'll override the
announced plan if I disagree.

---

## Stack all work on the current branch (once)

All issues stack on **one** branch — the branch you are **already on** when the batch starts. This
skill does **not** cut a new branch; it builds the whole stack **in place** on the current branch,
each issue on top of the commits of the ones before it. Do these steps **in this exact order** —
validate the branch first, then commit the issue files onto it, then record the base. (Recording the
base before the issue-files commit would make the first AFK issue's `HEAD == $BASE` assertion
spuriously fail, since HEAD then sits one commit *above* the recorded base.)

**On a resume** (a `$WTMP-progress.md` ledger and `$WTMP-branch` already exist), `resume.md` § branch
validation replaces steps 1–3 — follow it instead.

1. **Resolve and validate the current branch.** Run `git branch --show-current`, and resolve the
   default branch's name (`main`/`master` — `git symbolic-ref --short refs/remotes/origin/HEAD`,
   falling back to whichever of `main`/`master` exists; reuse it for the `<default>` placeholder
   below).
   - **Empty result (detached HEAD)** → halt; there's no branch to stack on.
   - **It *is* the default/protected branch** → **halt: tell me to switch to (or create) a working
     branch first.** Stacking TDD red-green churn and review commits directly onto the default branch
     is almost never intended, and the per-issue `/tdd-review-loop` subagent would refuse it anyway
     (its protected-branch gate auto-branches off `main`/`master`, which would break the single
     stack).
   - **Otherwise** → this is the stack branch (call it `<branch>`). Persist its name to `$WTMP-branch`
     and reuse it everywhere below.

2. **Dirty-tree check + commit the issue files.** Run `git status --porcelain`.
   The issue files (and any plan docs they reference under `## Parent`) are commonly **untracked** —
   and an untracked tree would trip the `/tdd-review-loop` subagent's own dirty-tree gate on **every**
   issue. Resolve it **once, now, autonomously**: **commit the issue files (and referenced plan docs)
   as the first batch commit on `<branch>`** (you are already on it) so the tree is clean for every
   subsequent run, and announce that you did so.

   If the tree has *other* changes **beyond** the issue/plan files, do **not** silently absorb them
   — they aren't yours to commit. **Halt**: tell me what they are and ask whether to stash, commit,
   or ignore them.

3. **Record the base sha — *after* the step-2 commit.** Persist `$WTMP-base` = `git rev-parse HEAD`
   **once the issue-files commit exists** (if the tree was already clean and nothing was committed,
   HEAD is just the current branch tip — that's fine). This sha is **the point the stack starts
   from** and is exactly what the first AFK issue asserts its `HEAD` against, so it **must** include
   the issue-files commit. Persist it so it survives a context drop.

---

## Main loop — one issue at a time, in topological order

**Strictly sequential — never run two AFK subagents at once.** They share the one working tree and
`/tdd-review-loop`'s deterministic `$TMP` prefix (a hash of the repo toplevel), so concurrent runs
would collide on the tree and on `/tmp` state and corrupt each other's diffs. Finish (or pause) one
issue before starting the next.

For each issue in order:

1. **Already DONE in the ledger?** Skip it (resume case).
2. **Blocker check.** Confirm every blocker is marked DONE in the ledger. By topological order they
   will be — *unless* a blocker was an unresolved HITL issue or a `/tdd-review-loop` run that
   failed/paused. **If any blocker is not DONE, do not start this issue** — pause the batch and tell me
   which blocker is outstanding.

3. **HITL issue → pause and hand to me.** Do **not** feed it to `/tdd-review-loop` (it's a TDD
   code-implementation loop; a decision/ADR issue with "no production code" has nothing to red-green).
   Instead:
   - Surface the issue's `## What to build` / decision list, tell me it needs human resolution, and
     **wait**.
   - **When I confirm it's resolved** (including any of its own acceptance criteria about updating
     downstream issues) → mark it `DONE` in the ledger, then **record its `tip` as the current
     `git rev-parse HEAD`**. A HITL issue has no subagent to return an `end_head_sha`, so you capture
     HEAD yourself the moment you mark it DONE — this is what the next AFK issue's `$BASE` chains off
     in step 4. (If the resolution committed downstream edits, HEAD already reflects them; if it
     committed nothing, HEAD is unchanged from the prior `tip`.)
   - **If I say skip it** → record it `SKIPPED`; its dependents are now blocked (step 2 will catch
     them).

4. **AFK issue → delegate to a `/tdd-review-loop --afk` subagent.**

   **a. Establish the base.** `$BASE` = the `tip` sha of the most recent DONE issue, or — if none is
   DONE yet — the branch's start point read from **`$WTMP-base`** (persisted in branch-setup step 3,
   above — i.e. HEAD *after* the issue-files commit, not the fork point; this is why it's on disk
   rather than only in context).

   **b. Assert `git rev-parse HEAD == $BASE`** before spawning. Three outcomes:
   - **HEAD == `$BASE`** → good; proceed to spawn (c).
   - **HEAD *above* `$BASE`** → a non-DONE issue left commits on the branch. Handle by case:
     - *Resuming the same PAUSED issue* (its own partial commits are what sit above `$BASE`):
       **rewind-and-respawn** (Vocabulary) — after the rewind the assertion holds.
     - *Starting a different issue, or proceeding past a SKIPPED one*: those stray commits would
       pollute this issue's diff — **stop and tell me** to unwind them back to `$BASE` first; don't
       spawn on a polluted base.
   - **HEAD *below* `$BASE`** → should be impossible (the stack only grows). Don't spawn — **stop and
     tell me**; the ledger and the branch disagree and need reconciling first.

   **c. Spawn one `general-purpose` subagent.** The subagent must have the `/tdd-review-loop` skill
   available. Keep two things distinct:
   - **The loop's argument line (what becomes its `$ARGUMENTS`) is *only* `--afk [--panel|--no-panel]
     <issue path>`** — `--afk` first, at most one panel token in the middle, the single issue-file
     path last, **nothing else**. The loop honors a flag only as the whole first or last token, so
     this exact order is load-bearing — don't reorder it, and don't stuff the sha or branch name onto
     the line. The panel token, if any, comes from `$WTMP-panel-pref` (re-read the file rather than
     trusting it survived in context; if it's absent, forward no panel flag and let the loop choose
     its own mode).
   - **`$BASE` and the stacked branch name go in the surrounding natural-language prompt as context,
     not on the argument line.** And `$BASE` is **informational only** — the loop re-derives its own
     `$BASE = git rev-parse HEAD` in its pre-flight, which coincides with the value you pass because you
     spawn it at exactly that HEAD. You pass it (and the branch name) only so the subagent can sanity-
     check where it is. *Your* use of `$BASE` is the HEAD assertion and rewind in (b), not the
     subagent's input.
   - **Explicitly instruct the subagent to implement on `<branch>` in place and NOT cut a new branch.**
     Your stack branch may be named anything, so the loop's protected-branch gate can't auto-classify
     it as caller-created — state it plainly in the prompt: "You are on `<branch>`, the feature branch
     I (the caller) created for this stacked work — implement on it in place; do **not** branch off it
     or cut a new `tdd-review-loop/*` branch." This is what satisfies the loop's pre-flight gate so it
     works on one stack instead of returning `BLOCKED:{protected_branch}`. (Branch-setup step 1
     already guaranteed `<branch>` is not the default branch, so the loop's auto-branch-off-`main`
     path won't trigger either.)

   The subagent runs the loop's full Phase 0–3 **inside its own context** and **returns only a compact
   result**:
   ```
   { issue, state: DONE | BLOCKED, ac_outcome, end_head_sha, guide_path, blocked_reason? }
   ```
   Field meanings: **`issue`** — the issue file path you passed (the loop echoes it back). **`state`** — `DONE` or `BLOCKED`
   (Vocabulary, above). **`ac_outcome`** — a short free-text line summarizing how the issue's
   `## Acceptance criteria` came out (e.g. `"all 4 AC green"` or `"3/4 green, AC#2 deferred"`); you
   store it verbatim and echo it in the final summary, you don't parse it. **`end_head_sha`** — HEAD
   after the loop's final commit, which becomes this issue's `tip` in the ledger. **`guide_path`** —
   path to the disposable Phase-3 self-test guide. **`blocked_reason`** — present **only** when
   `state: BLOCKED`; the loop's `BLOCKED:{reason, detail}` payload string (relay it to me).

   `--afk` seeds Phase 0 from the issue's `## Acceptance criteria` **verbatim** (no human confirm) and
   derives interface/behaviors from `## What to build` + `## Parent`. You do **not** relay its gates —
   there are none to relay; it only ever comes back DONE or BLOCKED.

   **d. Handle the result:**
   - **`state: DONE`** → mark it DONE in the ledger with its `end_head_sha` as the `tip` (step 5) and
     record its `guide_path`.
   - **`state: BLOCKED`** → relay `blocked_reason` to me and **pause the batch** at this issue — record
     it as PAUSED, do **not** auto-advance (a later issue may depend on it). It continues only when I
     direct, by rewind-and-respawn.
   - **Subagent dies or returns nothing parseable** → treat it as PAUSED with a note (same as BLOCKED);
     it continues the same way, by rewind-and-respawn.

5. **Record progress.** After each issue resolves, update `$WTMP-progress.md` (append-only ledger:
   issue path, final state DONE/SKIPPED/PAUSED, the **`tip:<sha>`** at which it finished (for an AFK
   DONE issue, the `end_head_sha` the subagent returned; for a HITL DONE issue, the `git rev-parse
   HEAD` you captured when marking it DONE per step 3 — either way this is what step 4 asserts the next
   issue's `$BASE` against), and a one-line note — e.g. AC summary or which gate it stopped at).
   Optionally tick the
   issue file's `## Acceptance criteria` checkboxes if I asked for it.

   **Also preserve the loop's timing journal** (AFK issues only): the subagent's phase-timing journal
   lives at the loop's own prefix (`/tmp/tdd-review-loop-<hash>-journal.md` — same shasum-of-`$TOP`
   recipe as `$WTMP`, different prefix) and the **next** loop run's pre-flight deletes it. Copy it the
   moment the subagent returns, in one command (recompute both prefixes inline):
   ```bash
   TOP=$(git rev-parse --show-toplevel) && H=$(printf %s "$TOP" | shasum | cut -c1-12) && cp "/tmp/tdd-review-loop-$H-journal.md" "/tmp/tdd-review-issues-$H-journal-<NN>.md"
   ```
   (`<NN>` = the issue's number; a missing source file just means that run produced no journal — note it
   and move on.) This is what makes a slow batch auditable after the fact.

6. **Collect the self-test guide.** Each subagent returns the **path** to its disposable Phase-3
   self-test guide in its result (it does **not** print the guide back to you). Record each path —
   you'll list them all at the end. Don't `git add` or commit these (they're disposable, per
   `/tdd-review-loop`'s own policy).

Between issues the tree is left clean by `/tdd-review-loop`'s own final gate, and HEAD has advanced —
so the next issue's run bases off the new HEAD and stacks on top.

---

## Resumability

The ledger `$WTMP-progress.md` **persists across invocations** — that is what makes a re-run a
resume. The moment pre-flight finds an existing ledger, read **`resume.md`** and follow it: it covers
reconciling the ledger against the issue set, the persisted panel preference, validating the
persisted branch, and recovering `$WTMP-base`.

---

## Final summary

When the loop finishes (all DONE, or paused/stopped at my direction), summarize for me:

- **Per-issue status** — DONE / HITL-resolved / SKIPPED / PAUSED, each with its outcome — for an AFK
  issue the `ac_outcome` from its subagent result; for a HITL-resolved or SKIPPED issue the resolution
  note (those have no subagent and so no `ac_outcome`) — and anything left contested or deferred.
- **The stacked branch** name (`<branch>`, the branch the batch ran on) and the batch's commit range
  on top of the recorded base — `git log <base>..<branch> --oneline`, where `<base>` is `$WTMP-base`
  (the issue-files commit sits at `<base>` itself; everything after it is the per-issue work).
- **All Phase-3 self-test-guide paths** so I can verify each slice by hand.
- **The per-issue journal copies** (`$WTMP-journal-<NN>.md`) — phase-by-phase timing per issue, if I
  want to see where the minutes went.
- A reminder that — inheriting `/tdd-review-loop`'s policy — **nothing was pushed or opened as a PR**
  unless I explicitly asked.

**After any pause/escalation:** once I reply, act on my directive and **resume the batch from where you
stopped** — the orchestrator's own run state persists on disk under `$WTMP-*` (the ledger, the parsed
set, the branch name). A PAUSED issue continues by rewind-and-respawn. If I say proceed, continue with
the next eligible issue; if I say stop, halt without advancing.

Throughout: stay in the repo's existing conventions, keep all work scoped to the issues, and do not
push or open a PR unless I ask.
