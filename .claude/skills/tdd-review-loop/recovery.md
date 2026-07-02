# Recovery and rare-path machinery

Read the section a `SKILL.md` pointer named. Everything here inherits `SKILL.md`'s definitions: durable state, `$TMP`, the scoped diff.

## Parse gates

Each parse gate writes a sentinel when it stops and deletes it only when its answer is persisted. **On any resume, an existing sentinel whose answer file is still absent means the gate is still open — re-ask it; never fall through.**

**Flag conflict (`--panel … --no-panel`, step 2):**
1. **Before stopping, persist the middle text** (everything between the two flag tokens) to `$TMP-conflict-middle.txt` — a recovery breadcrumb, NOT `$TMP-requirement.md`: that file must stay absent until step 5 resolves a real requirement, or the empty-check resume guard would see a stale empty breadcrumb and fail to fire. The middle text is raw — it may itself be a plan-doc *path* rather than prose; fine, it's only a breadcrumb for the wait window.
2. Write the `$TMP-panel-conflict-pending` sentinel, then stop and ask which mode I want — even if no requirement text remains after stripping. Record no `$PANEL_FLAG` until I answer.
3. On my answer: persist it to `$TMP-panel-flag` (plus `$TMP-panel-flag-expected`), delete the sentinel, and **drop the leading and trailing flag *tokens* specifically** — don't regex-replace, which can leave one behind — so re-parsing cannot re-detect the same conflict and loop. Re-read the breadcrumb and **re-evaluate from step 4, not step 5**: the empty-check must run in case no middle text remains, and step 5 then resolves path-vs-inline and persists `$TMP-requirement.md` for the first time this run.
- Resume rule: `$TMP-panel-conflict-pending` present + `$TMP-panel-flag` absent → re-ask the mode question rather than falling through to the Phase-2 heuristic.

**Empty requirement (step 4):** write `$TMP-requirement-pending` on stop; delete it only once a non-empty `$TMP-requirement.md` is persisted in step 5. Resume rule: key on the sentinel **alone**, regardless of `$TMP-requirement.md`'s state — the stripped `$ARGUMENTS` may be gone after a context drop, and the conflict breadcrumb deliberately lives in `$TMP-conflict-middle.txt` so `$TMP-requirement.md` stays absent until a real requirement resolves.

**Path confirm (step 5 — missing/unreadable/empty path, or a non-doc path awaiting confirmation):** write `$TMP-path-confirm-pending` recording the token on stop; delete it once step 5 persists the requirement. Resume rule: sentinel present + `$TMP-requirement.md` absent → re-ask; never silently treat the path string itself as the requirement. On a corrected path (or a rejected file plus a supplied requirement), **re-evaluate from step 4** — the empty-check must run before path-vs-inline — and don't re-run Pre-flight (its up-front `rm` already ran this run).

## Reviewer recovery

**Missing or unparseable round-1 `STATUS:`** — the single-mode reviewer, or the panel's post-merge reviewer, crashed, aborted, or returned nothing parseable, leaving the loop with no convergence signal. Never treat an absent `STATUS:` as `CONVERGED`. Recover in order:
1. **Reviewer still live** → `SendMessage` it once, asking only for the `STATUS:` line (handle from `$TMP-reviewer-id`).
2. **Dead, or still nothing parseable** → re-spawn a fresh `general-purpose` reviewer, **overwriting `$TMP-reviewer-id` the moment you spawn it** — overwrite, never append a second id, so later rounds target the live reviewer, not the corpse.
3. **Reconstruct its context from disk:** `$TMP-ac.md`; `$BASE` (from `$TMP-base.sha`) + the exclusion list (`$TMP-exclude.txt`); the requirement from `$TMP-requirement.md` (for a doc/confirmed-file run, equivalently the file at `$TMP-plan-path`); the implementation summary including which tests were bit from `$TMP-impl-summary.md`; panel mode: the merged findings from `$TMP-merged-r1.md`; plus any findings the dead reviewer already returned this round, best-effort from context — `$TMP-merged-r1.md` and the live scoped diff are authoritative, since round 1 isn't journaled yet. Fall back to `$ARGUMENTS`/the live scoped diff only if a file is somehow absent.
4. **Still no parseable `STATUS:`** → escalate rather than proceeding or declaring the run converged.

**Rounds 2–3 resume:** if `SendMessage` to the prior reviewer isn't available or the agent wasn't retained between rounds, re-spawn a fresh reviewer (overwriting `$TMP-reviewer-id`) and paste the full prior-round transcript from `$TMP-journal.md` — every prior finding, your fix/rebuttal for each, and the current status — so its context is reconstructed.

## Dirty-tree exclusion builder

For the interactive record-the-paths choice in git hygiene step 1. `$TMP-exclude.txt` holds one **raw, un-quoted** path per line. Build it NUL-safe (run under **bash** — `read -d ''` does the NUL splitting; the consumption recipe in `SKILL.md` is shell-agnostic):
```bash
: > "$TMP-exclude.txt"
while IFS= read -r -d '' entry; do
  printf '%s\n' "${entry:3}" >> "$TMP-exclude.txt"            # status-bearing field -> strip the 3-char status
  case "${entry:0:1}" in
    R|C) IFS= read -r -d '' old && printf '%s\n' "$old" >> "$TMP-exclude.txt" ;;  # paired old path: bare field, do NOT strip
  esac
done < <(git status --porcelain -z)
```
Why this exact shape:
- **Plain `cut -c4-` on non-`-z` output breaks twice:** porcelain C-quotes any path containing a space (`"a b.ts"` — the literal quotes then defeat the pathspec match), and `cut` can't see the NUL framing anyway.
- **Renames/copies are two fields, and only the first is status-bearing:** in `-z` mode a rename/copy is emitted as two NUL-separated fields with no `->` arrow, in **reverse** display order — the **new (destination)** path first, prefixed with the `R…`/`C…` status (strip its 3 chars), then the **old** path as a **bare field with NO status prefix — record it verbatim, do NOT strip 3 chars** (stripping `old/a.ts` → `/a.ts`, which git rejects as outside the repo with a fatal exit 128 that kills every scoped diff).
- **Record both sides of a rename:** git models it as delete-old + add-new, so excluding only the new path still leaks `D <old>` into the scoped diff.
- A raw porcelain line like ` M src/x.ts` fed straight to a pathspec silently excludes nothing.

## Shell notes (the Pre-flight commands)

Why the Pre-flight forms are load-bearing — read before "simplifying" any of them:
- **Guard `$TOP` before hashing.** A bare `$(git rev-parse --show-toplevel | shasum)` pipes git's output into `shasum` regardless of git's exit status — outside a work tree the empty string hashes to the *constant* `da39a3ee5e6b`, a shared prefix whose `rm -f` would clobber a concurrent run's state. The `[ -n "$TOP" ]` guard aborts instead.
- **Bare assignment, no leading `$`.** You *reference* it later as `$TMP`, but `$TMP=…` would expand the unset var and try to run `=/tmp/…` as a command.
- **`{ … ; } 2>/dev/null || true` around the glob `rm`.** Under zsh, on a clean/first run `"$TMP"-*` matches nothing and zsh aborts at glob expansion (`no matches found`, non-zero) **before `rm` runs** — the trailing `|| true` is what lets the run continue, and the brace-wrap is what routes the message to `/dev/null` (neither `-f` nor a bare `2>/dev/null` alone helps; the glob never reaches `rm`). A no-match here is normal, not a failure to stop on. (Equivalently: `rm -f` the named `$TMP-*` files individually, which never errors under `-f`.)
- **One prefix per tree is the right boundary:** runs in the *same* tree already collide on shared test artifacts (see the panel shared-tree caveat), so per-checkout granularity is deliberate.
