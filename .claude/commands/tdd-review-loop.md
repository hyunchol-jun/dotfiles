---
name: tdd-review-loop
description: Implement a requirement with the tdd skill, then run up to 3 rounds of adversarial review-and-rebuttal with a separate agent, and finish with a self-test guide. Use when given a bug fix or feature plan to implement end-to-end with review.
---

You are the **implementer agent** and you own this entire run. The requirement to implement is:

$ARGUMENTS

`$ARGUMENTS` is either an inline requirement/plan, or a path to a plan doc (e.g. `docs/some-plan.md`). If it looks like a file path, read that file and treat its contents as the requirement. If it's empty, ask me for the requirement before doing anything else.

**Round-1 mode flags:** if `$ARGUMENTS` begins or ends with the flag `--panel` or `--no-panel`, that flag controls the round-1 reviewer mode (see Phase 2) — record it as `$PANEL_FLAG`, then **strip it out** and treat the remaining text as the requirement. Match only this exact `--`-prefixed flag as a leading or trailing argument; never infer the mode from the bare word "panel" appearing inside the requirement text (e.g. "implement the admin **panel**" is a requirement, not a flag). If neither flag is present, `$PANEL_FLAG` is unset and the mode is chosen by heuristic in Phase 2.

Run the following phases in order. Do not skip phases. Narrate which phase and review round you're in as you go.

**Before anything else, record the base commit so diffs work for the whole run regardless of what gets committed later:**
```
git rev-parse HEAD
```
Call this `$BASE`. Throughout this run, "the diff" always means `git diff $BASE` plus `git status --porcelain` for any untracked files (and `git diff $BASE -- <new files>` once added). Never rely on a bare `git diff`, which shows only unstaged changes and will miss work that TDD has already committed or staged.

---

## Phase 0 — Acceptance criteria

Before writing any code, distill the requirement into an explicit, **numbered acceptance-criteria checklist** — each item a single observable behavior or constraint the finished work must satisfy, phrased so it can be objectively checked as met/unmet (not "handles errors well" but "returns a 422 with field-level messages when the payload is missing `email`"). Include negative/edge criteria where the requirement implies them.

Show me the checklist and **get my confirmation or edits before implementing.** If the requirement is a one-line bug fix, this can be a single criterion — but still write it down. This checklist (call it `$AC`) is the contract for the whole run: it scopes Phase 1, it's what the reviewer ticks off in Phase 2, and convergence is illegal while any criterion is unmet (see Phase 2). Keep it in your working notes and restate it to the reviewer verbatim.

## Phase 1 — Implement with TDD

Invoke the `/tdd` skill and implement the requirement using its red-green-refactor workflow. Follow `/tdd` fully, including confirming the interface and which behaviors to test with me where that skill calls for it. Every `$AC` criterion that warrants a test (per the scoping rules below) should map to at least one test.

**Frontend test scoping:** Do *not* write tests for frontend/UI code by default. Skip tests for presentational components, layout/styling, simple prop wiring, trivial event handlers, and thin glue that just calls a hook or renders data. Only write frontend tests when the code carries **non-trivial logic worth protecting** — e.g. meaningful data transformation/derivation, conditional branching with several states, form validation rules, reducers/state machines, custom hooks with real logic, or tricky edge-case handling. In that case, prefer testing the logic in isolation (extract it to a pure function/hook and test that) rather than rendering the whole component. When in doubt about whether a given piece of frontend logic is "complex enough," ask me before writing or skipping the test. This scoping rule applies only to frontend code; backend/business logic follows `/tdd` as normal.

**Note:** this phase is *not* fully autonomous — `/tdd` will pause to get my approval on the interface and the list of behaviors to test. That's expected; wait for my input at those checkpoints rather than guessing.

When implementation is complete, **gate the handoff on a fully green state**: run the entire test suite, plus typecheck and lint if the project has them. Everything must pass before moving to Phase 2 — don't make the reviewer burn a round on breakage you could catch here.

**Bite check (do this yourself before handoff):** for each of your 2–3 most important new tests, deliberately break the code it covers (flip a condition, drop a guard, return the wrong value) and confirm that test *fails*. Revert the break immediately. A test that stays green against broken code is not protecting anything — fix or strengthen it before handoff. Record which tests you bite-checked; you'll report this to the reviewer.

Then capture a summary of what you built (files changed, key decisions, the diff via `git diff $BASE`, the `$AC` checklist with each item mapped to where it's satisfied + tested, and your bite-check results) — you'll hand this to the reviewer.

## Phase 2 — Review loop (up to 3 rounds)

### Round-1 mode: single reviewer vs. reviewer panel

Round 1 is the discovery round — breadth matters most here. You may run it either as a single reviewer or as a parallel **panel** of lens-specialized reviewers whose findings you merge. Rounds 2–3 are *always* a single-reviewer dialogue regardless of round-1 mode (see below).

Decide the mode before spawning anything, in this order:
1. **If `$PANEL_FLAG` is set:** `--panel` → use the panel; `--no-panel` → use a single reviewer. The flag always wins.
2. **Otherwise, heuristic on the Phase 1 diff:** use the **panel** if the diff touches **≥3 files** OR has **≥~150 changed lines** OR touches core business logic / a known high-risk area; otherwise use a **single reviewer**.

**Announce-and-proceed:** state in one line which mode you're using and why (e.g. "Round-1 mode: panel — diff touches 6 files / 240 lines" or "Round-1 mode: single — 1 file, 18 lines"), then proceed. Don't stop to ask; I'll override if I disagree.

**Panel mode — round 1 only.** Spawn 3–4 `general-purpose` reviewers in parallel (single message, multiple tool calls). Give each the same round-1 reviewer context (requirement, `$AC`, `$BASE`, implementation summary, evidence gate, frontend scoping rule), with two differences: assign each a distinct **lens** and tell it to confine its findings to that lens, and tell it it is **read-only** — it may read, run the suite as-is, and report, but must not edit/mutate the tree (panelists share one working tree, so any mutation corrupts the others' reads) and must **not** emit a `STATUS:` line (convergence is judged only by the single reviewer in the dialogue rounds). The lenses:
- **correctness** — logic bugs, wrong outputs, broken control flow, mishandled return values.
- **edge-cases / concurrency** — boundaries, nulls/empties, error paths, races, ordering, partial failures.
- **requirements-coverage** — walk the `$AC` checklist; find criteria that are unmet, partially met, or untested.
- **test-quality** — by inspection only: find weak, tautological, or non-biting tests and untested logic, and **nominate** the 2–3 tests most worth a bite audit (don't run the audit — that's deferred to the serial step below).

(For a smaller-but-still-panel-worthy diff, drop to 3 lenses by folding edge-cases into correctness.)

When all panelists return, **merge their findings** into one numbered list: collapse entries only when they describe the **same defect / root cause** (not merely the same `file:line`), keeping the highest severity and strongest evidence; demote any blocker/should-fix that failed the evidence gate to an unverified `nit`; and carry the test-quality lens's bite-audit nominations forward separately. This merged list is the round-1 result. (Panelists are discarded after round 1 — don't try to resume them.)

Then spawn **one** `general-purpose` reviewer and hand it the merged list as the round-1 findings. It now has the tree to itself, so **before** it responds, have it run the **test-bite audit serially** on the nominated tests (plus any others it judges important): break the covered code, confirm the test fails, revert. Any test that stays green against broken behavior becomes a `blocker` ("test does not bite") added to the findings. Then proceed with rounds 2–3 as the single-reviewer dialogue below.

**Single-reviewer mode (and rounds 2–3 of both modes):**
Spawn a **single** reviewer subagent with the `general-purpose` agent type and keep using that same agent across all rounds via `SendMessage` (so its context and prior findings are preserved — this is a real dialogue, not three fresh reviews).

**Fallback if the reviewer can't be resumed:** if `SendMessage` to the prior reviewer isn't available or the agent wasn't retained between rounds, re-spawn a fresh `general-purpose` reviewer and paste the full prior-round transcript into its prompt — every prior finding, your fix/rebuttal for each, and the current status — so its context is reconstructed. Never let the loop silently degrade into three context-free reviews.

**Round 1 reviewer context** (give this to the single reviewer, or to *each* panelist in panel mode):
- The original requirement **and the `$AC` checklist verbatim.**
- A summary of the implementation, and `$BASE` so it can pull the diff itself with `git diff $BASE`. Instruct it to **actually explore the surrounding code and run the test suite itself** — it has the tools — rather than reviewing the pasted diff in isolation, so it can verify claims and catch integration issues.
- Instruct it to act as an adversarial code reviewer: find correctness bugs, missed requirements, missing/weak test coverage, edge cases, and design problems. Return a numbered list of findings, each with severity (blocker / should-fix / nit) and a concrete rationale.
- **Evidence gate (required for every blocker and should-fix):** each such finding must cite a specific `file:line`, **and** carry proof it's real — *either* a failing test the reviewer actually wrote and ran (paste the test and the failure output) *or* exact reproduction steps (commands + observed vs. expected output). A finding at blocker/should-fix severity **without** a repro must be demoted to `nit` and labeled "unverified — could not reproduce." This applies the same skeptic's burden to the reviewer that it applies to you: no plausible-but-unproven blockers.
- **Acceptance-criteria pass:** walk the `$AC` checklist and mark each criterion met / unmet / untested-but-met, citing where in the code/tests each is satisfied. Any unmet criterion is at least a `should-fix` (a blocker if it's core to the requirement). *(In panel mode this is the **requirements-coverage** lens's job; other panelists skip it.)*
- **Test-bite audit:** independently pick 2–3 of the most important tests, deliberately break the covered code, and confirm the test fails (then revert). Any test that stays green against broken behavior is a `blocker` ("test does not bite"). I already did a self bite-check on [the tests you bit] — spot-check *different* tests where possible. *(This bullet is for the **single reviewer**. In panel mode the panelists are read-only and skip it; the bite audit instead runs serially after the merge — see the panel section above.)*
- Tell it about the **frontend test scoping rule** from Phase 1: trivial/presentational frontend code is intentionally left untested, so it should **not** raise "missing test coverage" findings for it. It *may* flag missing frontend tests only where the code carries genuinely non-trivial logic (data transforms, multi-state branching, validation, reducers/state machines, logic-bearing hooks) that was left untested. Backend/business-logic coverage is still fair game as usual.
- Instruct it to **end every response with an explicit status line** so the loop is machine-checkable: either `STATUS: CONVERGED` or `STATUS: OPEN — blockers:N should-fix:M nits:K ac-unmet:U bite-failures:B`.

**Convergence is illegal** (the reviewer may not emit `STATUS: CONVERGED`) while *any* of these hold: an open blocker or should-fix, an unmet `$AC` criterion, or a test that failed the bite audit. `CONVERGED` means all findings resolved, every `$AC` criterion met, all audited tests bite, and all your rebuttals conceded.

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
- You complete **3 rounds** → stop regardless. Do not exceed 3 rounds. If any `blocker` is still open or contested, any `$AC` criterion is still unmet, or any test still fails the bite audit at this point, escalate to me rather than declaring the run done.

**Final green gate (required before you may exit the loop, however it stopped):** rounds 2–3 only re-run the tests and bite audit, so a late fix can introduce a type or lint error that nothing else catches. Before declaring the run done, re-run the **entire test suite, plus typecheck and lint if the project has them** — exactly the same gate as the Phase 1 handoff (line 38). Everything must be green. If anything fails, fix it (in TDD style where a test is warranted) and re-run until green; if you can't get it green within reason, escalate to me rather than exiting on a red gate.

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
