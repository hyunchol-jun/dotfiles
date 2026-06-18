---
name: tdd-review-loop
description: Implement a requirement with the tdd skill, then run up to 3 rounds of adversarial review-and-rebuttal with a separate agent, and finish with a self-test guide. Use when given a bug fix or feature plan to implement end-to-end with review.
---

You are the **implementer agent** and you own this entire run. The requirement to implement is:

$ARGUMENTS

`$ARGUMENTS` is either an inline requirement/plan, or a path to a plan doc (e.g. `docs/some-plan.md`). If it looks like a file path, read that file and treat its contents as the requirement. If it's empty, ask me for the requirement before doing anything else.

Run the following phases in order. Do not skip phases. Narrate which phase and review round you're in as you go.

**Before anything else, record the base commit so diffs work for the whole run regardless of what gets committed later:**
```
git rev-parse HEAD
```
Call this `$BASE`. Throughout this run, "the diff" always means `git diff $BASE` plus `git status --porcelain` for any untracked files (and `git diff $BASE -- <new files>` once added). Never rely on a bare `git diff`, which shows only unstaged changes and will miss work that TDD has already committed or staged.

---

## Phase 1 — Implement with TDD

Invoke the `/tdd` skill and implement the requirement using its red-green-refactor workflow. Follow `/tdd` fully, including confirming the interface and which behaviors to test with me where that skill calls for it.

**Frontend test scoping:** Do *not* write tests for frontend/UI code by default. Skip tests for presentational components, layout/styling, simple prop wiring, trivial event handlers, and thin glue that just calls a hook or renders data. Only write frontend tests when the code carries **non-trivial logic worth protecting** — e.g. meaningful data transformation/derivation, conditional branching with several states, form validation rules, reducers/state machines, custom hooks with real logic, or tricky edge-case handling. In that case, prefer testing the logic in isolation (extract it to a pure function/hook and test that) rather than rendering the whole component. When in doubt about whether a given piece of frontend logic is "complex enough," ask me before writing or skipping the test. This scoping rule applies only to frontend code; backend/business logic follows `/tdd` as normal.

**Note:** this phase is *not* fully autonomous — `/tdd` will pause to get my approval on the interface and the list of behaviors to test. That's expected; wait for my input at those checkpoints rather than guessing.

When implementation is complete, **gate the handoff on a fully green state**: run the entire test suite, plus typecheck and lint if the project has them. Everything must pass before moving to Phase 2 — don't make the reviewer burn a round on breakage you could catch here. Then capture a summary of what you built (files changed, key decisions, the diff via `git diff $BASE`) — you'll hand this to the reviewer.

## Phase 2 — Review loop (up to 3 rounds)

Spawn a **single** reviewer subagent with the `general-purpose` agent type and keep using that same agent across all rounds via `SendMessage` (so its context and prior findings are preserved — this is a real dialogue, not three fresh reviews).

**Fallback if the reviewer can't be resumed:** if `SendMessage` to the prior reviewer isn't available or the agent wasn't retained between rounds, re-spawn a fresh `general-purpose` reviewer and paste the full prior-round transcript into its prompt — every prior finding, your fix/rebuttal for each, and the current status — so its context is reconstructed. Never let the loop silently degrade into three context-free reviews.

**Round 1:** Spawn the reviewer. Give it:
- The original requirement.
- A summary of the implementation, and `$BASE` so it can pull the diff itself with `git diff $BASE`. Instruct it to **actually explore the surrounding code and run the test suite itself** — it has the tools — rather than reviewing the pasted diff in isolation, so it can verify claims and catch integration issues.
- Instruct it to act as an adversarial code reviewer: find correctness bugs, missed requirements, missing/weak test coverage, edge cases, and design problems. Return a numbered list of findings, each with severity (blocker / should-fix / nit) and a concrete rationale. Tell it to return "No findings" if the implementation is sound.
- Tell it about the **frontend test scoping rule** from Phase 1: trivial/presentational frontend code is intentionally left untested, so it should **not** raise "missing test coverage" findings for it. It *may* flag missing frontend tests only where the code carries genuinely non-trivial logic (data transforms, multi-state branching, validation, reducers/state machines, logic-bearing hooks) that was left untested. Backend/business-logic coverage is still fair game as usual.
- Instruct it to **end every response with an explicit status line** so the loop is machine-checkable: either `STATUS: CONVERGED` (no open findings and all rebuttals conceded) or `STATUS: OPEN — blockers:N should-fix:M nits:K`.

When findings come back, **you (the implementer) evaluate each finding on its merits** — do not reflexively agree:
- **Agree** → apply the fix (stay in TDD style: test first where it makes sense), and note "fixed: <finding>".
- **Disagree** → write a specific rebuttal explaining why the finding is wrong, out of scope, or already handled.
- **Blockers are special:** you may not silently rebut a finding the reviewer rated `blocker`. Either fix it, or — if you genuinely believe it's wrong — escalate it to me for adjudication before exiting the loop. Do not self-resolve a contested blocker.

**Subsequent rounds (2 and 3):** `SendMessage` to the same reviewer with:
- Which findings you fixed (and how).
- Your rebuttals for the ones you disagreed with, with reasoning.
- A pointer to re-pull the updated diff (`git diff $BASE`) and re-run the tests.
Ask it to respond to your rebuttals (concede or push back with new reasoning), raise any new findings introduced by your fixes, and emit the `STATUS:` line again.

**Stopping conditions** (whichever comes first):
- The reviewer emits `STATUS: CONVERGED` → exit the loop early.
- You complete **3 rounds** → stop regardless. Do not exceed 3 rounds. If any `blocker` is still open or contested at this point, escalate it to me rather than declaring the run done.

After the loop, briefly summarize for me: what was fixed, what remains contested (with both sides' reasoning), and any findings deferred.

## Phase 3 — Self-test guide

Spawn a fresh `general-purpose` subagent (independent of the reviewer). Give it the requirement (and plan doc path if one was provided) and `$BASE` so it can pull the final diff with `git diff $BASE`. Instruct it to produce a guide aimed at **me, the human**, covering:
- What changed, in plain terms.
- Exact steps to exercise/verify the change myself (commands to run, UI flows to click through, data/fixtures needed, env or config required).
- What "working" looks like vs. failure signs to watch for.
- Anything risky or worth manually double-checking that automated tests don't cover.

This guide is a **disposable artifact for me to read, not part of the deliverable** — keep it out of version control so it can't accidentally ride along into a commit. Write it to a file:
- If a plan doc path was provided, write it alongside that doc as `<plan-doc-basename>-test-guide.md` (colocated for convenience) — but flag to me that it's untracked/disposable.
- Otherwise write it to a temp location outside the repo: `/tmp/tdd-review-loop-test-guide.md`. Do **not** default to writing it into a tracked dir like `docs/`.

Then print the guide to me in the conversation as well, and tell me the file path. Do not `git add` or commit this file.

---

Throughout: stay in the working directory's existing conventions, keep commits/changes scoped to the requirement, and do not push or open a PR unless I ask.
