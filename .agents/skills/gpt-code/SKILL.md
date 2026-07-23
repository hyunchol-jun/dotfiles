---
name: gpt-code
description: Multi-model coding loop — a Claude subagent (fable/opus) plans, Codex CLI (GPT) implements, a Claude subagent judges the diff, up to 3 rounds. Flags select models and effort.
disable-model-invocation: true
---

You orchestrate a plan → code → judge loop across two model families. The task is:

$ARGUMENTS

Claude (via subagents you spawn with the Agent tool) plans and judges. Codex CLI (GPT, via Bash) writes the code. The filesystem and git are the only handoff: Codex edits files headlessly and exits; the judge reviews `git diff`, never Codex's self-report.

## Parse `$ARGUMENTS`

Flags may appear anywhere before the task text; strip each one you honor. Everything remaining is the task.

| Flag | Values | Default | Applies to |
|---|---|---|---|
| `--claude <m>` | `fable`, `opus`, `sonnet`, `haiku` | session model (omit `model` param) | planner AND judge subagents (Agent tool `model` param) |
| `--planner <m>` | same | falls back to `--claude` | planner subagent only |
| `--judge <m>` | same | falls back to `--claude` | judge subagent only |
| `--coder <m>` | any Codex model id, passed verbatim (e.g. `gpt-5.5-codex`, `gpt-5.4`) | Codex's configured default (omit `-m`) | `codex exec -m <m>` |
| `--effort <e>` | passed verbatim (Codex accepts `minimal`/`low`/`medium`/`high`) | Codex default (omit the override) | `codex exec -c model_reasoning_effort=<e>` |
| `--rounds <n>` | 1–5 | 3 | judge-loop cap |

Claude-side effort is NOT per-flag switchable — the Agent tool has no effort parameter; planner/judge inherit the session's effort. `--effort` governs Codex only. If the task text is empty after flag-stripping, stop and ask for it.

Announce the resolved config in one line before starting: `plan/judge: <model> · coder: <model or "codex default"> @ <effort or "default"> · max rounds: N`.

## Pre-flight

1. `command -v codex` — missing → stop and tell me to install it (`npm i -g @openai/codex` or `brew install codex`) and authenticate (`codex login`). Don't install it yourself.
2. Confirm a git repo with commits (`git rev-parse --verify HEAD`).
3. **Dirty tree:** if `git status --porcelain` is non-empty, stop and ask — stash, commit, or proceed with the dirty paths recorded for exclusion. The judge must review Codex's work only.
4. If on `main`/`master`, create a branch `gpt-code/<short-task-slug>` and announce it.
5. Record `$BASE = git rev-parse HEAD`. Create the run directory `.gpt-code/` at the repo toplevel; if it isn't git-ignored, that's fine — you delete it in Finish and it's excluded from every diff below.

**The scoped diff**, used by the judge every round and in the final report:
```bash
git diff $BASE -- . ':(exclude).gpt-code' && git ls-files --others --exclude-standard -- . ':(exclude).gpt-code'
```
Both halves — new untracked files are invisible to `git diff` alone. Run from the repo toplevel. Add `:(exclude)<path>` for any recorded pre-existing dirty paths.

## Phase 1 — Plan

Spawn a planner subagent (Agent tool, `subagent_type: general-purpose`, `model` per the resolved planner model) with the task text. It must explore the codebase and write a spec to `.gpt-code/plan.md` containing:

- The requirement in its own words, plus repo context Codex will need (conventions, key files with paths, existing patterns to follow).
- Files to create/modify, with the intended shape of each change.
- Numbered **acceptance criteria** — observable behaviors, objectively checkable.
- Exact commands to run tests/typecheck/lint for this repo, and the instruction that all must pass.
- What NOT to do (no drive-by refactors, no dependency additions unless listed, no edits under `.gpt-code/`).

The plan is the contract: Codex sees only this file, not the conversation. Read it after the subagent returns; if it's vague or missed the point, redo it with feedback rather than handing junk to Codex.

## Phase 2 — Code (Codex)

Run via Bash with `run_in_background: true` (Codex runs can exceed the foreground timeout):

```bash
cd "$(git rev-parse --show-toplevel)" && codex exec --full-auto \
  ${CODER:+-m "$CODER"} ${EFFORT:+-c model_reasoning_effort="$EFFORT"} \
  "Implement the plan in .gpt-code/plan.md exactly. Read it first. Run the test/typecheck/lint commands it names and make them pass. Do not modify anything under .gpt-code/." \
  2>&1 | tee .gpt-code/codex-round-1.log
```

(Substitute the resolved model/effort literally; drop the `-m`/`-c` parts when using defaults. If `--full-auto` is rejected by the installed Codex version, retry with `--dangerously-bypass-approvals-and-sandbox` and say so.)

When it exits: skim the log tail for hard failures (auth errors, refusals, zero-change runs). If the scoped diff is empty, Codex did nothing — surface the log and stop rather than judging an empty diff.

## Phase 3 — Judge loop (up to `--rounds` rounds)

Spawn ONE judge subagent (Agent tool, `general-purpose`, `model` per the resolved judge model) and keep it across rounds via SendMessage — a dialogue, not fresh reviews. Its brief:

- Read `.gpt-code/plan.md`. Pull the scoped diff itself (give it `$BASE`, the recipe verbatim, and any exclusions). Explore surrounding code; run the test/typecheck/lint commands from the plan — verify, don't trust the log.
- Walk the acceptance criteria: met / unmet, citing where each is satisfied.
- Adversarial findings, each with severity (`blocker` / `should-fix` / `nit`) and a concrete `file:line` rationale. Plan-scope discipline: code that matches the plan is not a finding just because the judge would have designed it differently.
- End every response with `VERDICT: PASS` or `VERDICT: FAIL` followed by the numbered findings. `PASS` is illegal while any blocker, should-fix, or unmet criterion is open. Nits don't block.

**On FAIL:** write the findings verbatim to `.gpt-code/review-N.md`, then re-run Codex (same command shape, log to `codex-round-<N+1>.log`) with:

```
Your previous implementation of .gpt-code/plan.md was reviewed. Read .gpt-code/review-N.md and fix every numbered finding. Do not undo unrelated working code. Re-run the plan's test commands and make them pass.
```

Then SendMessage the judge: findings were addressed, re-pull the diff, re-verify, verdict again.

**Stop when:** `VERDICT: PASS`, or the round cap hits. At the cap with open findings, do NOT loop further and do NOT fix Codex's work yourself silently — present the open findings and ask: another round, I fix it by hand, you (main session) finish it, or accept as-is.

## Finish

1. `rm -rf .gpt-code/` — it's scaffolding, never part of the deliverable.
2. Verify the scoped diff still passes tests (the rm can't break anything, but a paranoid re-run of the suite is cheap; skip if the judge ran it this round).
3. Report: verdict, rounds used, acceptance criteria with final status, files changed (`git diff $BASE --stat`), and anything contested or deferred. Do not commit or push unless I ask.

Throughout: never edit implementation files yourself — the division of labor IS the skill. Your fixes go through Codex via review files; the only exception is the explicit hand-back at the round cap.
