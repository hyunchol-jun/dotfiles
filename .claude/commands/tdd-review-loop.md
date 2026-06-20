---
name: tdd-review-loop
description: Implement a requirement with the tdd skill, then run up to 3 rounds of adversarial review-and-rebuttal with a separate agent, and finish with a self-test guide. Use when given a bug fix or feature plan to implement end-to-end with review.
---

You are the **implementer agent** and you own this entire run. The requirement to implement is:

$ARGUMENTS

`$ARGUMENTS` is either an inline requirement/plan, or a path to a plan doc (e.g. `docs/some-plan.md`). If it looks like a file path, read that file and treat its contents as the requirement. If it's empty, ask me for the requirement before doing anything else.

**Round-1 mode flags:** if `$ARGUMENTS` begins or ends with the flag `--panel` or `--no-panel`, that flag controls the round-1 reviewer mode (see Phase 2) — record it as `$PANEL_FLAG`, then **strip it out** and treat the remaining text as the requirement. Match only this exact `--`-prefixed flag as a leading or trailing argument; never infer the mode from the bare word "panel" appearing inside the requirement text (e.g. "implement the admin **panel**" is a requirement, not a flag). If neither flag is present, `$PANEL_FLAG` is unset and the mode is chosen by heuristic in Phase 2. **After stripping the flag, if no requirement text remains** (e.g. I passed only `--panel`), treat it the same as an empty `$ARGUMENTS` and ask me for the requirement before doing anything else.

Run the following phases in order. Do not skip phases. Narrate which phase and review round you're in as you go.

**Pre-run git hygiene (do this before capturing the base commit):**
1. **Confirm a git repo with commits:** run `git rev-parse --is-inside-work-tree` and `git rev-parse HEAD`. If either fails (not a repo, or zero commits), stop and tell me — every later `git diff $BASE` depends on this.
2. **Check for a dirty starting tree:** run `git status --porcelain`. If it's non-empty, the working tree already has changes that would otherwise be wrongly attributed to this requirement (folded into the diff the reviewer, the `$AC` pass, the bite audit, and the Phase-3 guide all consume). **Stop and ask me** how to proceed — stash, commit, or explicitly record the pre-existing paths so you can exclude them from "the diff" throughout. Do not silently absorb them.
3. **Branch off the default/protected branch:** run `git branch --show-current`. If it's the default branch (`main`/`master`) or otherwise protected, `/tdd`'s red-green-refactor commits and bite-audit reverts would land directly on it. Create a feature branch (or ask me which) before Phase 1 so the run's commits are isolated.

**Then record the base commit so diffs work for the whole run regardless of what gets committed later:**
```
git rev-parse HEAD
```
Call this `$BASE`. Throughout this run, "the diff" always means `git diff $BASE` plus `git status --porcelain` for any untracked files (and `git diff $BASE -- <new files>` once added), **minus any pre-existing paths recorded in step 2**. Never rely on a bare `git diff`, which shows only unstaged changes and will miss work that TDD has already committed or staged.

---

## Phase 0 — Acceptance criteria

Before writing any code, distill the requirement into an explicit, **numbered acceptance-criteria checklist** — each item a single observable behavior or constraint the finished work must satisfy, phrased so it can be objectively checked as met/unmet (not "handles errors well" but "returns a 422 with field-level messages when the payload is missing `email`"). Include negative/edge criteria where the requirement implies them.

Show me the checklist and **get my confirmation before implementing.** If I give edits, apply them and **restate the final checklist, then loop** — confirm again — until I approve it with no further edits (don't proceed on your own interpretation of an edit). If the requirement is a one-line bug fix, this can be a single criterion — but still write it down. This checklist (call it `$AC`) is the contract for the whole run: it scopes Phase 1, it's what the reviewer ticks off in Phase 2, and convergence is illegal while any criterion is unmet (see Phase 2).

**Persist `$AC` so it survives verbatim across subagent handoffs:** once I approve it, write the final checklist to `/tmp/tdd-review-loop-ac.md` (the same disposable-file pattern this command uses for `$BASE` and the Phase-3 guide). Treat that file as the source of truth and **re-read it** at each handoff (every reviewer spawn, every `SendMessage`, the Phase-3 spawn) rather than relying on it staying intact in your context — paste its exact contents into each subagent prompt.

## Phase 1 — Implement with TDD

Invoke the `/tdd` skill and implement the requirement using its red-green-refactor workflow. Follow `/tdd` fully, including confirming the interface and which behaviors to test with me where that skill calls for it. Every `$AC` criterion that warrants a test (per the scoping rules below) should map to at least one test.

**Frontend test scoping:** Do *not* write tests for frontend/UI code by default. Skip tests for presentational components, layout/styling, simple prop wiring, trivial event handlers, and thin glue that just calls a hook or renders data. Only write frontend tests when the code carries **non-trivial logic worth protecting** — e.g. meaningful data transformation/derivation, conditional branching with several states, form validation rules, reducers/state machines, custom hooks with real logic, or tricky edge-case handling. In that case, prefer testing the logic in isolation (extract it to a pure function/hook and test that) rather than rendering the whole component. When in doubt about whether a given piece of frontend logic is "complex enough," ask me before writing or skipping the test. This scoping rule applies only to frontend code; backend/business logic follows `/tdd` as normal.

**Note:** this phase is *not* fully autonomous — `/tdd` will pause to get my approval on the interface and the list of behaviors to test. That's expected; wait for my input at those checkpoints rather than guessing.

When implementation is complete, **gate the handoff on a fully green state**: run the entire test suite, plus typecheck and lint if the project has them. Everything must pass before moving to Phase 2 — don't make the reviewer burn a round on breakage you could catch here. **If `/tdd` can't reach green within reason** (the implementation keeps failing and you're stuck), escalate to me rather than handing off red or thrashing — the same stop-and-ask discipline the Phase 2 gates apply.

**Bite check (do this yourself before handoff):** for each of your 2–3 most important new tests, deliberately break the code it covers (flip a condition, drop a guard, return the wrong value) and confirm that test *fails*, then revert. A test that stays green against broken code is not protecting anything — fix or strengthen it before handoff. Record which tests you bite-checked; you'll report this to the reviewer.

**Make every bite revert-safe** (here and everywhere else this run breaks-then-reverts code — the reviewer's bite audit too): snapshot before breaking and restore from the snapshot rather than hand-editing the break back, so a crash mid-break can't leave the tree broken. Concretely: stash or commit clean state first (e.g. `git stash` / a throwaway WIP commit, or note the exact `git checkout -- <file>` that restores it), break, observe the failure, then **restore from the snapshot** and verify `git diff $BASE` is back to where it was. If you ever find the tree broken with no record of how to restore it, stop and tell me rather than guessing.

**Zero-test branch:** if the requirement legitimately warrants no tests (e.g. a purely presentational frontend change under the scoping rule above), the test-centric gates degrade gracefully — make that explicit rather than inventing tests to satisfy them: the bite check and the reviewer's bite audit are **N/A**, "all audited tests bite" is **vacuously true**, and both green gates fall back to **typecheck + lint + manual `$AC` verification** (walk each criterion by hand, since there are no tests to assert it). Say so in your handoff summary so the reviewer doesn't raise "missing tests" against an intentionally test-free change.

Then capture a summary of what you built (files changed, key decisions, the diff via `git diff $BASE`, the `$AC` checklist with each item mapped to where it's satisfied + tested, and your bite-check results) — you'll hand this to the reviewer.

## Phase 2 — Review loop (up to 3 rounds)

### Round-1 mode: single reviewer vs. reviewer panel

Round 1 is the discovery round — breadth matters most here. You may run it either as a single reviewer or as a parallel **panel** of lens-specialized reviewers whose findings you merge. Rounds 2–3 are *always* a single-reviewer dialogue regardless of round-1 mode (see below).

Decide the mode before spawning anything, in this order:
1. **If `$PANEL_FLAG` is set:** `--panel` → use the panel; `--no-panel` → use a single reviewer. The flag always wins.
2. **Otherwise, heuristic on the Phase 1 diff:** use the **panel** if the diff touches **≥3 files** OR has **≥150 changed lines** (measure with `git diff $BASE --shortstat`: insertions + deletions) OR touches core business logic / a known high-risk area; otherwise use a **single reviewer**.

**Announce-and-proceed:** state in one line which mode you're using and why (e.g. "Round-1 mode: panel — diff touches 6 files / 240 lines" or "Round-1 mode: single — 1 file, 18 lines"), then proceed. Don't stop to ask; I'll override if I disagree.

**Panel mode — round 1 only.** Spawn 3–4 `general-purpose` reviewers in parallel (single message, multiple tool calls). Give each the same round-1 reviewer context (requirement, `$AC`, `$BASE`, implementation summary, evidence gate, frontend scoping rule), with two differences: assign each a distinct **lens** and tell it to confine its findings to that lens, and tell it it is **read-only** — it may read and report, but must not edit/mutate the tree.

**Shared-tree caveat (important — the panel shares one working tree):** there is no harness-level write lock, so "read-only" is an *instruction the panelist may still violate*, and **concurrent test runs collide** on non-namespaced artifacts (`.pytest_cache`, coverage files, `__pycache__`, snapshots, `dist`/`build`/`target`, test DBs, fixed ports), producing flaky failures a panelist would then misreport as a real finding. So do **not** have all panelists run the suite. Choose one:
- **Preferred — give each panelist its own checkout:** `git worktree add` a throwaway worktree at `$BASE` per panelist (clean each up afterward). Then they may each run the suite safely.
- **Otherwise — single source of truth:** have exactly **one** panelist (or none) run the suite; the others review statically and against the green suite output you already captured at the Phase 1 handoff. Tell the static panelists explicitly: do not run the suite.

Either way, tell every panelist it must **not** emit a `STATUS:` line (convergence is judged only by the single reviewer in the dialogue rounds). The lenses:
- **correctness** — logic bugs, wrong outputs, broken control flow, mishandled return values.
- **edge-cases / concurrency** — boundaries, nulls/empties, error paths, races, ordering, partial failures.
- **requirements-coverage** — walk the `$AC` checklist; find criteria that are unmet, partially met, or untested.
- **test-quality** — by inspection only: find weak, tautological, or non-biting tests and untested logic, and **nominate** the 2–3 tests most worth a bite audit (don't run the audit — that's deferred to the serial step below).

(For a smaller-but-still-panel-worthy diff, drop to 3 lenses by folding edge-cases into correctness.)

When all panelists return, **first restore a clean tree:** remove any per-panelist worktrees you created, then run `git status --porcelain` and `git diff $BASE` and confirm the tree still matches the Phase 1 handoff state — if a panelist mutated it despite the read-only instruction, `git checkout`/`git stash` the stray changes away before continuing. Then **merge their findings** into one numbered list: collapse entries only when they describe the **same defect / root cause** (not merely the same `file:line`), keeping the highest severity and strongest evidence; demote any blocker/should-fix that failed the evidence gate to an unverified `nit`; and carry the test-quality lens's bite-audit nominations forward separately. This merged list is the round-1 result. (Panelists are discarded after round 1 — don't try to resume them.)

Then spawn **one** `general-purpose` reviewer and hand it the merged list as the round-1 findings. It now has the tree to itself, so **before** it responds, have it run the **test-bite audit serially** on the nominated tests (plus any others it judges important): break the covered code, confirm the test fails, revert. Any test that stays green against broken behavior becomes a `blocker` ("test does not bite") added to the findings. **This reviewer is the one that judges convergence, so instruct it to emit the `STATUS:` line in this first response** (covering the merged list plus its bite-audit result) — otherwise panel mode has no round-1 convergence signal and a clean diff can't exit early. Then proceed with rounds 2–3 as the single-reviewer dialogue below.

**Single-reviewer mode (and rounds 2–3 of both modes):**
Spawn a **single** reviewer subagent with the `general-purpose` agent type and keep using that same agent across all rounds via `SendMessage` (so its context and prior findings are preserved — this is a real dialogue, not three fresh reviews). **Record the reviewer's agent id/name the moment you spawn it** (note it in your working state) so `SendMessage` resume is the reliable path in rounds 2–3 and you don't lose the handle.

**Fallback if the reviewer can't be resumed:** if `SendMessage` to the prior reviewer isn't available or the agent wasn't retained between rounds, re-spawn a fresh `general-purpose` reviewer and paste the full prior-round transcript into its prompt — every prior finding, your fix/rebuttal for each, and the current status — so its context is reconstructed. Never let the loop silently degrade into three context-free reviews.

**Round 1 reviewer context** (give this to the single reviewer, or to *each* panelist in panel mode):
- The original requirement **and the `$AC` checklist verbatim.**
- A summary of the implementation, and `$BASE` so it can pull the diff itself with `git diff $BASE`. Instruct it to **actually explore the surrounding code and run the test suite itself** — it has the tools — rather than reviewing the pasted diff in isolation, so it can verify claims and catch integration issues.
- Instruct it to act as an adversarial code reviewer: find correctness bugs, missed requirements, missing/weak test coverage, edge cases, and design problems. Return a numbered list of findings, each with severity (blocker / should-fix / nit) and a concrete rationale.
- **Evidence gate (required for every blocker and should-fix):** each such finding must cite a specific `file:line`, **and** carry proof it's real — *either* a failing test the reviewer actually wrote and ran (paste the test and the failure output) *or* exact reproduction steps (commands + observed vs. expected output). A finding at blocker/should-fix severity **without** a repro must be demoted to `nit` and labeled "unverified — could not reproduce." This applies the same skeptic's burden to the reviewer that it applies to you: no plausible-but-unproven blockers.
- **Leave the tree as you found it:** a written evidence test is by definition *failing* and would either ride into the deliverable diff or turn the implementer's final green gate red on a test it never authored. So the reviewer must paste its evidence/scratch tests into the report rather than leaving them in the tree: after gathering evidence and running the bite audit, **delete every scratch/evidence test and revert every bite break**, then confirm `git diff $BASE` is back to implementation-only before responding. The tree handed back must contain only the implementer's work.
- **Acceptance-criteria pass:** walk the `$AC` checklist and mark each criterion met / unmet / untested-but-met, citing where in the code/tests each is satisfied. Any unmet criterion is at least a `should-fix` (a blocker if it's core to the requirement). *(In panel mode this is the **requirements-coverage** lens's job; other panelists skip it.)*
- **Test-bite audit:** independently pick 2–3 of the most important tests, deliberately break the covered code, and confirm the test fails (then revert). Any test that stays green against broken behavior is a `blocker` ("test does not bite"). I already did a self bite-check on [the tests you bit] — spot-check *different* tests where possible. *(This bullet is for the **single reviewer**. In panel mode the panelists are read-only and skip it; the bite audit instead runs serially after the merge — see the panel section above.)*
- Tell it about the **frontend test scoping rule** from Phase 1: trivial/presentational frontend code is intentionally left untested, so it should **not** raise "missing test coverage" findings for it. It *may* flag missing frontend tests only where the code carries genuinely non-trivial logic (data transforms, multi-state branching, validation, reducers/state machines, logic-bearing hooks) that was left untested. Backend/business-logic coverage is still fair game as usual.
- Instruct it to **end every response with an explicit status line** so the loop is machine-checkable: either `STATUS: CONVERGED` or `STATUS: OPEN — blockers:N should-fix:M nits:K ac-unmet:U bite-failures:B`.

**Convergence is illegal** (the reviewer may not emit `STATUS: CONVERGED`) while *any* of these hold: an open blocker or should-fix, an unmet `$AC` criterion, or a test that failed the bite audit. `CONVERGED` means every blocker and should-fix is **resolved**, every `$AC` criterion is met, and all audited tests bite. A finding counts as **resolved** when it is *either fixed, or its rebuttal accepted by the reviewer* — a sustained rebuttal that the reviewer accepts is a valid resolution, not a blocker to convergence. (Open `nit`s do **not** block `CONVERGED`; only blockers and should-fixes do.)

When findings come back, **you (the implementer) evaluate each finding on its merits** — do not reflexively agree:
- **Agree** → apply the fix (stay in TDD style: test first where it makes sense), and note "fixed: <finding>".
- **Disagree** → write a specific rebuttal explaining why the finding is wrong, out of scope, or already handled. For an evidence-backed finding, your rebuttal must address the repro directly (show why the repro is invalid or the behavior is actually correct).
- **Blockers are special:** you may not silently rebut a finding the reviewer rated `blocker`. Either fix it, or — if you genuinely believe it's wrong — escalate it to me for adjudication before exiting the loop. Do not self-resolve a contested blocker.

**Subsequent rounds (2 and 3):** `SendMessage` to the same reviewer with:
- Which findings you fixed (and how).
- Your rebuttals for the ones you disagreed with, with reasoning.
- A pointer to re-pull the updated diff (`git diff $BASE`) and re-run the tests.
Ask it to respond to your rebuttals (concede or push back with new reasoning), re-check any `$AC` criteria your fixes touched, re-run the bite audit on any tests your fixes changed, raise any new findings introduced by your fixes, and emit the `STATUS:` line again.

**Stopping conditions** (whichever comes first):
- The reviewer emits `STATUS: CONVERGED` → exit the loop early.
- You complete **3 rounds** → stop regardless. Do not exceed 3 rounds. If at this point any `blocker` is still open or contested, any **should-fix is still open or contested** (the reviewer sustains it and you haven't fixed it — it is not a "resolved" finding), any `$AC` criterion is still unmet, or any test still fails the bite audit, escalate to me rather than declaring the run done.

**Final green gate (required before you may exit the loop, however it stopped):** rounds 2–3 only re-run the tests and bite audit, so a late fix can introduce a type or lint error that nothing else catches. Before declaring the run done, re-run the **entire test suite, plus typecheck and lint if the project has them** — exactly the same gate as the Phase 1 handoff. Everything must be green. **Also verify the tree is implementation-only:** run `git status --porcelain` and `git diff $BASE` and confirm nothing remains from a reviewer's scratch/evidence test or an un-reverted bite break — the diff must contain only your implementation and tests, scoped to the requirement. If anything fails or the tree is dirty with non-implementation changes, fix/clean it (in TDD style where a test is warranted) and re-run until green; if you can't get it green within reason, escalate to me rather than exiting on a red gate.

After the loop, briefly summarize for me: the `$AC` checklist with final met/unmet status, what was fixed, what remains contested (with both sides' reasoning), and any findings deferred.

## Phase 3 — Self-test guide

Spawn a fresh `general-purpose` subagent (independent of the reviewer). Give it the requirement (and plan doc path if one was provided), the `$AC` checklist, and `$BASE` so it can pull the final diff with `git diff $BASE`. Instruct it to produce a guide aimed at **me, the human**, covering:
- What changed, in plain terms.
- Exact steps to exercise/verify the change myself (commands to run, UI flows to click through, data/fixtures needed, env or config required) — organized so each `$AC` criterion has a way for me to check it by hand.
- What "working" looks like vs. failure signs to watch for.
- Anything risky or worth manually double-checking that automated tests don't cover.

This guide is a **disposable artifact for me to read, not part of the deliverable** — keep it out of version control so it can't accidentally ride along into a commit. Write it to a file:
- If a plan doc path was provided, write it alongside that doc as `<plan-doc-basename>-test-guide.md` (colocated for convenience) — but flag to me that it's untracked/disposable.
- Otherwise write it to a temp location outside the repo: `/tmp/tdd-review-loop-test-guide.md`. Do **not** default to writing it into a tracked dir like `docs/`.

Then print the guide to me in the conversation as well, and tell me the file path. Do not `git add` or commit this file.

---

Throughout: stay in the working directory's existing conventions, keep commits/changes scoped to the requirement, and do not push or open a PR unless I ask.
