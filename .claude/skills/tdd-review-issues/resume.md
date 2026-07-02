# Resuming a batch

Read this when pre-flight finds an existing `$WTMP-progress.md` ledger. It replaces nothing in
`SKILL.md` except branch-setup steps 1–3 (see § Validate the branch); everything else there still
applies.

## Reconcile the ledger against the issue set

- Parse the issue set as normal, then reconcile: issues marked **DONE** are skipped; the main loop
  re-enters at the first **non-DONE** issue.
- If the issue **set has changed** since the ledger was written (files added/removed/reordered),
  point that out, recompute the plan, and **announce it** before resuming — re-confirm with me only
  when the change invalidates work already marked DONE (e.g. a DONE issue's file was removed or its
  blockers rewritten); otherwise proceed on the recomputed plan.

## Panel preference

A flagless re-invocation leaves any existing `$WTMP-panel-pref` intact — don't delete the mode
chosen on the original run. Only an explicit `--panel`/`--no-panel` passed on the resume overrides
it. (The fresh-run `rm -f "$WTMP-panel-pref"` in the parse section applies only when no ledger
exists.)

## Validate the branch (replaces branch-setup steps 1–3)

- Confirm `git branch --show-current` still equals the persisted `$WTMP-branch`. If it differs — I
  switched branches since the original run — **halt** and tell me, naming both branches, rather than
  silently stacking onto a different branch.
- If it matches, **skip the issue-files commit and base capture** (they already happened on the
  original run) and **trust `$WTMP-base`** for the stack base. Skipping the commit step also skips
  the orchestrator's up-front dirty-tree check — each spawned `/tdd-review-loop` run still runs its
  own dirty-tree gate, so stray out-of-set changes are still caught before any issue's diff is
  computed.

## Recover `$WTMP-base` if missing

Recover it as the **issue-files commit** — the first commit on the branch past the fork point (the
child of the fork point, *not* the fork point itself):

```bash
git rev-list --max-parents=1 <default>..<branch> | tail -1
```

then rewrite `$WTMP-base`.

## PAUSED issues

A PAUSED AFK issue continues only by **rewind-and-respawn** (`SKILL.md` § Vocabulary) — never by
expecting the loop to pick up where it left off.
