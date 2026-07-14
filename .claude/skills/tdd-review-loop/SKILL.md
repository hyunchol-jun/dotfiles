---
name: tdd-review-loop
description: Implement a requirement with the tdd skill, then run adversarial review-and-rebuttal rounds with a separate agent (capped at 2 autonomous / 3 interactive), and finish with a self-test guide. Use when given a bug fix or feature plan to implement end-to-end with review.
---

You are the **implementer agent** and you own this entire run. The requirement to implement is:

$ARGUMENTS

Run the phases below in order. Do not skip phases. Narrate which phase and review round you're in as you go.

Sibling files in this skill's directory — read one only when a pointer below names it:
- `panel.md` — the round-1 reviewer-panel branch of Phase 2.
- `recovery.md` — rare-path machinery: parse-gate sentinels and resume rules, reviewer crash recovery, the dirty-tree exclusion builder, and shell notes explaining why the Pre-flight commands take their exact forms.

## Modes

**Autonomous (default).** This skill is built to run headless — driven by the documentation it's given (an acceptance-criteria checklist, a plan doc, the issue's `## What to build`, the repo's conventions) — reaching a human only for genuine blockers. One global rule translates every "stop and ask me" below: **decide from the documentation and announce-and-proceed** — state your decision in one line and continue; the caller overrides if it disagrees. **At a genuine blocker, do NOT invent a default: emit a structured `BLOCKED:{reason, one-line detail}` line and stop.** How a `BLOCKED` surfaces is set by context, not by you: if a human is present in this thread, present it and wait; if you were spawned as a subagent (e.g. by `/tdd-review-issues`), the `BLOCKED:{…}` line **is** your return value — stop and return it, the caller relays it. You never silently push past a genuine blocker, and you never sit waiting on a prompt no one will answer.

**Interactive (`--interactive`).** Every "stop and ask me" prompts the human and waits. Use when a human deliberately drives the run by hand. Parsed per Parse `$ARGUMENTS`.

**The genuine-blocker set** (these `BLOCKED`/stop in *both* modes — never auto-defaulted): a stuck Phase 1, a contested `blocker`, the round cap with findings still open, a red final green gate, an acceptance-criteria set that is missing/incoherent or contradicts the plan, a genuinely undetermined or sensitive interface, a dirty starting tree, an unresolvable requirement input (a missing/unreadable/empty requirement path, or an empty requirement after flag-stripping), and inconsistent on-disk run state on resume. Everything else is doc-driven in autonomous mode.

## Durable state

`$ARGUMENTS` is a one-time template expansion and your context can be lost to a mid-run summarization; the run's state lives on disk instead. The discipline, applied everywhere below without restating it: **persist a value the moment it's decided; re-read it from disk at the moment of use; never trust it surviving in context across a phase boundary or subagent handoff.** All state hangs off one deterministic prefix `$TMP` (computed in Pre-flight; if you ever lose it mid-run, recompute it exactly the same way). The full set this run may write:

`$TMP-base.sha`, `$TMP-ac.md`, `$TMP-requirement.md`, `$TMP-requirement-pending`, `$TMP-conflict-middle.txt`, `$TMP-path-confirm-pending`, `$TMP-branch`, `$TMP-exclude.txt`, `$TMP-panel-flag`, `$TMP-panel-flag-expected`, `$TMP-panel-conflict-pending`, `$TMP-plan-path`, `$TMP-mode-flag`, `$TMP-pre-snapshot.sha`, `$TMP-impl-summary.md`, `$TMP-reviewer-id`, `$TMP-merged-r1.md`, `$TMP-test-guide.md`, and the append-only `$TMP-journal.md`.

**Phase timing:** at every phase/round transition, append one line `- $(date +%FT%T) — <phase or round label>` to `$TMP-journal.md` — it costs nothing and makes where the minutes went auditable after the run.

Pre-flight clears them all up front, so **absence reliably means "not produced this run"** — several are written only conditionally (`-pending` files are sentinels that exist only while a gate is waiting; `$TMP-branch` only once a branch is created; `$TMP-reviewer-id` only once a reviewer is spawned). A path that never writes one must not read a stale copy from a prior run.

## Pre-flight (do this first, before parsing `$ARGUMENTS`)

1. **Confirm a git repo with commits.** `git rev-parse --is-inside-work-tree` must print the literal `true` (a bare repo prints `false` yet still exits 0), and `git rev-parse --verify HEAD` must succeed (it fails on a commit-less or bare repo; bare `git rev-parse HEAD` does not — it prints the literal string `HEAD` on a missing ref, so its status is not a dependable presence check). If either fails, stop and tell me — every later `git diff $BASE` depends on this.
2. **Compute `$TMP` and clear prior state.** Run exactly this — the forms are load-bearing; before editing any of them, read the shell notes in `recovery.md`:
```bash
TOP=$(git rev-parse --show-toplevel) && [ -n "$TOP" ] || { echo "no work tree — aborting" >&2; exit 1; }
TMP=/tmp/tdd-review-loop-$(printf %s "$TOP" | shasum | cut -c1-12)   # bare assignment — no leading $
{ rm -f "$TMP"-* ; } 2>/dev/null || true                            # clear every $TMP-<name> file from a prior crashed run
: > "$TMP-journal.md"                                                # journal is append-only — (re)create it empty
```
   The prefix is deterministic per checkout and distinct across worktrees, so concurrent runs in different trees never clobber each other.

## Parse `$ARGUMENTS`

`$ARGUMENTS` is an inline requirement/plan or a path to a plan doc (e.g. `docs/some-plan.md`), optionally wrapped in a round-1 mode flag (`--panel`/`--no-panel`) and/or an execution-mode flag (`--afk`/`--autonomous`/`--interactive`).

**Flag detection discipline (all flags):** a token counts only when the **whole first or last whitespace-delimited token** equals it, matched case-sensitively as an ASCII literal (two ASCII hyphens). `--PANEL`, a unicode-dash `—panel`, or a token like `--panel-feature.md` that merely starts with the string does not match. A mid-text occurrence is requirement prose, never a flag ("implement the admin **panel**" is a requirement) — even an *opposite* flag buried mid-text (`--panel do X --no-panel ASAP`, last token not a flag) is intentionally prose, not a conflict; the Phase-2 announce line plus my override is the safety net.

**Execution mode:** autonomous is the default. `--afk`/`--autonomous` explicitly affirm it (self-documenting callers, unaffected if the default ever changes) and write nothing; `--interactive` overrides — persist the literal token to `$TMP-mode-flag` (absence = autonomous; re-read it wherever a gate decides announce-vs-prompt). If both an affirming flag and `--interactive` appear, `--interactive` wins; announce that. Strip every honored mode token before the empty-check; mode and round-1 flags are independent and may co-occur.

Parse the rest in this exact order — conflict check **before** empty check. **Every "stop and ask me" gate in this parse is a genuine blocker:** autonomous mode cannot invent a requirement from nothing — emit `BLOCKED:{empty_requirement}` (step 4) or `BLOCKED:{bad_requirement_path}` (steps 2 and 5) instead of prompting. **Each gate that stops must first write its recovery sentinel — the sentinel mechanics and resume rules live in `recovery.md` § Parse gates; read that section the moment any gate here fires or you resume with a `-pending` file present.**

1. **Detect the round-1 flag** (`--panel`/`--no-panel`, first/last token per the discipline above). No match → `$PANEL_FLAG` stays unset and Phase 2 falls through to its heuristic.
2. **Conflict check** — only when `$ARGUMENTS` has ≥2 tokens AND both leading and trailing tokens are flags (a lone `--panel` is one token — straight to step 3). Identical flags agree: record and persist per step 3, then strip both. Disagreeing flags (`--panel … --no-panel`) are a gate: follow `recovery.md` § Parse gates — persist the middle text as a breadcrumb, stop and ask which mode (even if no requirement text remains), and on the answer resume from step 4 with both flag tokens dropped. Don't let the empty-check pre-empt this.
3. **Record and persist the flag.** Write the literal token (`--panel` or `--no-panel`, verbatim — never normalized; Phase 2 matches that exact string) to `$TMP-panel-flag` **immediately**, plus the `$TMP-panel-flag-expected` sentinel alongside it (it lets Phase 2 tell "no flag ever set" apart from "flag set but its file lost"). Then strip only the leading/trailing token(s) you honored — never a mid-text one (`--panel do X --no-panel ASAP` → `do X --no-panel ASAP`).
4. **Empty check.** If the remaining text is empty — originally, or after flag-stripping (e.g. a lone `--panel`) — gate: write `$TMP-requirement-pending`, then ask me for the requirement (interactive) or `BLOCKED:{empty_requirement}` (autonomous). `$PANEL_FLAG` persists across the re-prompt (it's on disk) and applies to the requirement then supplied. Treat the supplied text as the new remaining text and run step 5 on it.
5. **Path vs. inline (decide on the *remaining* text).** It "looks like a file path" only if it is a single whitespace-free token that contains a `/` separator or ends in a `.<ext>` suffix whose extension is alphabetic (`.ts`, `.md`, `.yaml`). Multi-word text (even containing a slash, like "fix a/b testing bucket assignment"), a bare word with no extension, or a slash-free token whose only dotted suffix is numeric/version-like (`v1.2`, `node18.4`) is an **inline requirement**. (Precedence: a token containing `/` is path-like regardless of suffix — `release/v1.2` is a path; the version-suffix exclusion applies only to slash-free tokens.)
   - **Resolve against the repo toplevel first:** `PLAN=$TOP/<token>` (an already-absolute token as-is, avoiding a `$TOP//abs` double slash). Run every check and read against `$PLAN`, never the bare token — the harness may reset your cwd between calls, and a repo-relative read from the wrong cwd would spuriously trip the gate below.
   - **Path-like but missing, unreadable, or empty (check FIRST, before the doc/non-doc split):** gate — write `$TMP-path-confirm-pending` recording the token, then stop and ask (naming whether it *looked* like a plan doc or a source/config file, so I can correct the path) or `BLOCKED:{bad_requirement_path}`. On a corrected path, re-evaluate from step 4 — not 5; the empty-check must run — and don't re-run Pre-flight (its `rm` already ran this run).
   - **Doc extension** (`.md`/`.txt`/`.rst`/`.markdown`), readable and non-empty: its contents are the requirement. Persist `$PLAN` — the **absolute** path, because Phase 3 and recovery re-read it from subagents whose cwd is not guaranteed — to `$TMP-plan-path`.
   - **Path-like, readable, but NOT a doc extension** (`src/auth/session.ts`, `infra/deploy.yaml`, `config.json`): could be source/config, not a plan. Don't silently distill criteria from it — gate: write `$TMP-path-confirm-pending`, confirm with me (or `BLOCKED:{bad_requirement_path}`). Confirmed as the plan → proceed exactly like the doc branch (persist `$TMP-plan-path`). Rejected → ask for the actual requirement, re-evaluate from step 4, and do NOT persist `$TMP-plan-path` (a rejected path is not a plan doc; its absence keeps Phase 3 and recovery correctly treating the run as plan-doc-less).

   **Whichever branch resolves the requirement** (inline text, a doc's contents, or a confirmed file's contents), persist the final text to `$TMP-requirement.md` and delete any pending sentinel the resolution just satisfied.

## Pre-run git hygiene (before capturing the base commit)

1. **Dirty starting tree:** if `git status --porcelain` is non-empty, the tree has pre-existing changes that would be wrongly attributed to this requirement (folded into everything downstream that consumes the diff). **Autonomous:** do not stash/commit/guess — `BLOCKED:{dirty_tree, <paths>}`. (`/tdd-review-issues` commits its issue files before spawning you, so a clean batch handoff never trips this gate.) **Interactive:** stop and ask — stash, commit, or record the pre-existing paths for exclusion. To record them, build `$TMP-exclude.txt` with the NUL-safe builder in `recovery.md` § Dirty-tree exclusion builder — plain `cut -c4-` on porcelain output silently breaks on spaced paths and renames; use the builder. That file is the canonical exclusion set for the whole run.
2. **Branch off the default/protected branch** (`git branch --show-current`): `/tdd`'s red-green-refactor commits and bite-audit reverts must not land on `main`/`master` or a protected branch. **Autonomous:** on `main`/`master`, branch to `tdd-review-loop/<short-slug-of-requirement>`, announce, proceed — don't ask. On a non-personal branch you cannot classify as a feature branch created for this work, `BLOCKED:{protected_branch}` — **but when your caller's spawn prompt explicitly says it created the current branch for this stacked work (as `/tdd-review-issues` does — on a branch that may be named anything), trust that statement as authoritative and implement in place, no new branch.** A `tdd-review-loop/*` or `tdd-review-issues/*` name also classifies as caller-created. **Interactive:** branch protection lives on the remote and may not be queryable from here, so don't assume a non-main branch is unprotected — ask unless it's an obviously-personal branch you created this run. On `main`/`master`, branching is effectively mandatory: ask only for the *name* (default above); if I insist on staying, require an explicit acknowledgement that commits will land there. When you branch, persist the chosen name to `$TMP-branch`. If the name is taken (a prior or crashed run), don't let `git checkout -b` fail with exit 128 — verify-before-create with a bounded loop: `slug=tdd-review-loop/<base>; n=1; while git show-ref --verify --quiet "refs/heads/$slug"; do slug=tdd-review-loop/<base>-$n; n=$((n+1)); [ $n -gt 5 ] && break; done` then `git checkout -b "$slug"`; still taken after the cap → stop and ask for an alternate name.

**Record the base commit:** `$BASE = git rev-parse HEAD`. Persist immediately to `$TMP-base.sha` — once `/tdd` starts committing, HEAD can no longer re-derive it.

### The scoped diff

Throughout this run, **"the scoped diff"** means exactly this recipe — and *every* site that consumes the run's changes (the Phase-2 mode heuristic, every reviewer and panelist, the reviewer's leave-tree-clean check, the final green gate, the Phase-3 guide) uses it, no other form:

```
args=(. )
[ -f "$TMP-exclude.txt" ] && while IFS= read -r p; do [ -n "$p" ] && args+=( ":(exclude)$p" ); done < "$TMP-exclude.txt"
git diff $BASE -- "${args[@]}"                             # tracked + already-committed changes
git ls-files --others --exclude-standard -- "${args[@]}"  # untracked files git diff $BASE can't see — inspect each's contents too
```

- **Both halves are mandatory.** `git diff $BASE` alone is blind to untracked files, and the common TDD outcome — a new source module plus a new test file, still untracked at handoff — would be invisible without the `ls-files` half.
- **Never a bare `git diff`** — unstaged-only; it misses work TDD already committed or staged.
- **Never a `$(sed …)`/`$(cat …)` command-substitution** to build the excludes — it word-splits any multi-word path into separate *positive* pathspecs that silently invert the exclusion (restricting the diff instead of excluding), exit 0, no error.
- **Run from the repo toplevel `$TOP`** — `.` is cwd-relative; a subagent in a subdirectory would otherwise scope the diff to it.
- **When handing to a subagent:** paste `$BASE` (from `$TMP-base.sha`) and the contents of `$TMP-exclude.txt` into its prompt, with this recipe verbatim — both halves — and the run-from-`$TOP` instruction, so it sees the same scoped diff you do.

If no exclusions were recorded, `$TMP-exclude.txt` is absent, the `[ -f ]` guard leaves the exclusion set empty, and the recipe degrades to a bare `git diff $BASE` + untracked listing — already correct.

---

## Phase 0 — Acceptance criteria

Before writing any code, distill the requirement into an explicit, **numbered acceptance-criteria checklist** — each item a single observable behavior or constraint, phrased so it can be objectively checked as met/unmet (not "handles errors well" but "returns a 422 with field-level messages when the payload is missing `email`"). Include negative/edge criteria the requirement implies. Mark purely presentational criteria (spacing, font, layout) as verifiable only by human eye — they get verified by human visual check, never asserted "met" by a headless agent.

**Autonomous:** if the requirement already carries a checklist (e.g. the issue's `## Acceptance criteria` — `/to-issues` output is already human-approved), **adopt it verbatim** as `$AC`, persist it, announce in one line, and go straight to Phase 1 — no re-distilling, no confirming. Otherwise distill one as above, announce, proceed without waiting. `BLOCKED:{ac_missing}` only if you cannot form a coherent checklist at all; `BLOCKED:{ac_contradicts}` if the supplied criteria materially contradict the requirement/plan (e.g. `## Acceptance criteria` and `## What to build` disagree).

**Interactive:** show me the checklist and **get my confirmation before implementing**. On edits: apply them, restate the final checklist, and confirm again — loop until I approve with no further edits (never proceed on your own interpretation of an edit). A one-line bug fix can be a single criterion, but still write it down; you may fold that single-criterion confirmation into the same message as your implementation plan — folding saves a round-trip, it does not waive the wait for approval.

This checklist is **`$AC`** — the contract for the whole run: it scopes Phase 1, the reviewer ticks it off in Phase 2, and convergence is illegal while any criterion is unmet. Persist it to `$TMP-ac.md` and paste its exact contents into every **fresh subagent spawn** (each reviewer/panelist spawn, each recovery re-spawn) — but never re-paste it into a `SendMessage` to the live reviewer, which already holds it in context; that's pure token burn each round.

## Phase 1 — Implement with TDD

Invoke the `/tdd` skill and implement the requirement using its red-green-refactor workflow, in full. Every `$AC` criterion that warrants a test (per the scoping below) maps to at least one test.

**Pass the execution mode through to `/tdd`** (re-read `$TMP-mode-flag`): in autonomous mode tell `/tdd` it is running autonomously, so it derives the public interface and behaviors-to-test from `$AC` + the plan doc + repo conventions and announces-and-proceeds at its Planning checkpoints, escalating `BLOCKED:{interface_underdetermined}` / `BLOCKED:{sensitive_surface}` only on a genuinely undetermined or sensitive interface. In interactive mode let `/tdd` confirm the interface and behaviors with me at its checkpoints — wait there rather than guessing.

**Frontend test scoping:** do *not* write tests for frontend/UI code by default — presentational components, layout/styling, simple prop wiring, trivial event handlers, thin glue. Test only **non-trivial logic worth protecting**: meaningful data transformation/derivation, multi-state conditional branching, form validation rules, reducers/state machines, logic-bearing custom hooks, tricky edge-case handling — preferring the logic extracted to a pure function/hook and tested in isolation over rendering the component. Interactive: collect all in-doubt scoping calls and raise them together at `/tdd`'s behaviors-to-test checkpoint, so I draw the trivial/non-trivial line once. Autonomous: apply the line mechanically — >1 conditional branch or any real data derivation/transformation → extract and test; otherwise skip; announce the calls you made; `BLOCKED:{test_scope_borderline}` only for a borderline touching money/validation/data-integrity. Backend/business logic follows `/tdd` as normal.

**Green gate at handoff:** run the entire test suite, plus typecheck and lint if the project has them. Everything passes before Phase 2 — don't make the reviewer burn a round on breakage you could catch here. If `/tdd` can't reach green within reason (~3 consecutive failed attempts on the same failure, or the same test/error oscillating with no net advance — that's "stuck"), escalate (`BLOCKED:{phase1_stuck}`) rather than handing off red or thrashing.

**Bite check (yourself, before handoff — exception-only):** a test that was observed failing in its RED phase has already proven it bites; do **not** re-bite it — that re-proves what red-green just proved and burns a snapshot/break/run/restore cycle per test. Bite only tests that never had a red phase: added or substantially rewritten during refactor, or whose assertions changed after green. For each such test, deliberately break the code it covers (flip a condition, drop a guard, return the wrong value), confirm it *fails*, revert. A test that stays green against broken code is not protecting anything — fix or strengthen it before handoff. Under strict `/tdd` this set is normally **empty**. Record which tests (if any) you bit and which never had a red phase; the reviewer needs both.

**Every bite is revert-safe** — here and in the reviewer's Phase-2 audit: snapshot before breaking (`git stash`, a throwaway WIP commit, or note the exact `git checkout -- <file>` that restores), break, observe the failure, **restore from the snapshot** — never hand-edit the break back — and verify the scoped diff is back where it was. **Every bite is also file-scoped:** confirm the failure by running only the bitten test's file (or narrower — a single test by name), never the full suite; a bite proves one test fires against broken code, and full-suite confirmation multiplies runs for no extra signal. The full suite is reserved for the two green gates. A crash mid-break must not leave the tree broken; if you ever find it broken with no restore record, stop and tell me rather than guessing.

**Zero-test branch:** if the requirement legitimately warrants no tests (e.g. purely presentational under the scoping rule), the test-centric gates degrade gracefully — make that explicit rather than inventing tests: your bite check and the reviewer's bite audit are **N/A**, "all audited tests bite" is vacuously true, and both green gates fall back to **typecheck + lint + manual `$AC` verification** (walk each criterion by hand; presentational criteria are "pending human visual check," never "verified met"). Say so in the handoff summary so the reviewer doesn't raise "missing tests" against an intentionally test-free change. *Every later mention of "the zero-test case" refers to this paragraph.*

**Handoff summary:** files changed, key decisions, the scoped diff, the `$AC` checklist with each item mapped to where it's satisfied + tested, and your bite-check record — **which tests (if any) you bit and which never had a red phase** (that drives the reviewer's bite-audit priorities). Persist to `$TMP-impl-summary.md` — a raw diff recovers the code but not the decisions or which tests were bit.

## Phase 2 — Review loop (up to 2 rounds autonomous, 3 interactive)

### Round-1 mode: light vs. single vs. panel

Round 1 is the discovery round — breadth matters most. It runs as a single reviewer (at **light** or standard depth) or as a parallel panel of lens-specialized reviewers whose findings you merge. Later rounds are *always* a single-reviewer dialogue regardless.

Decide before spawning anything, in this order:
1. **`$PANEL_FLAG` wins.** Re-read it from `$TMP-panel-flag`: `--panel` → panel (never light), `--no-panel` → no panel — light vs. standard single still follows step 2's size split. If `$TMP-panel-flag` is absent/empty, check `$TMP-panel-flag-expected`: sentinel also absent → no flag was ever set, fall through to the heuristic. Sentinel **present** but the flag file gone → a flag *was* chosen and lost to a context drop — do NOT run the heuristic (it could flip an explicit `--no-panel` to panel on a sensitive diff, the opposite of what I chose); stop and ask which mode, then re-persist `$TMP-panel-flag`.
2. **Heuristic on the Phase-1 scoped diff:** panel iff **`(≥6 files)` OR `(≥400 changed lines)` OR `(sensitive-path AND (>20 changed lines OR spans >1 sensitive file))`** — *sensitive* = security-, money-, or data-integrity-sensitive (auth, payments, billing, permissions, migrations, deletion/PII). The thresholds are deliberately high: a TDD change touches 3+ files by construction (source + test + export/config), so a lower bar would spin up a 5-agent panel on routine medium changes a single reviewer handles fine. The grouping matters: a 1–2 line fix on a sensitive path **alone** does not qualify (don't spin up a 4-reviewer panel for it), while ≥6 files or ≥400 lines qualifies regardless of sensitivity. Measure with `git diff $BASE --shortstat` scoped by the exclusion recipe (a dirty starting tree must not inflate the count), **plus untracked files** via `git ls-files --others --exclude-standard` — not `git status --porcelain`, which collapses an entirely-new directory to a single `?? dir/` entry and undercounts; get untracked *line* counts by `wc -l` per file, or `git add -N` then re-run `--shortstat`. Note `--shortstat` omits any zero-count clause (a pure-add prints only `N insertions(+)`; an empty diff prints nothing) — a missing clause is 0, not a failed measurement. At the other end of the same measurement: **light iff `(<3 files AND <100 changed lines AND no sensitive path)`**; everything between light and panel is a standard single reviewer.

**Announce-and-proceed** the mode in one line ("Round-1 mode: light — 2 files, 40 lines", "single — 4 files, 220 lines", or "panel — 7 files / 440 lines"); don't stop to ask.

**Light tier** — the same single reviewer with three reductions; everything else (the `$AC` pass, the AC-completeness check, convergence rules, leave-tree-as-found) is unchanged:
1. The evidence gate accepts **exact repro steps only** — the reviewer does not write or run failing evidence tests.
2. The **test-bite audit is skipped** — every test already proved itself in its red phase; if the handoff names tests that never had one, the reviewer bites just those.
3. Rounds are fix-verification only (already the norm below).

A light diff is by definition small and non-sensitive, so written-repro tests and a bite audit buy little beyond the red phase plus the final gate — the depth belongs on medium+ diffs.

**Panel mode →** follow `panel.md` (in this skill's directory) for all of round 1: spawning the lens panel, the read-only evidence gate, teardown, merging findings into `$TMP-merged-r1.md`, and spawning the post-merge reviewer. **That post-merge reviewer then IS the single reviewer below for rounds 2–3** — its handle is already in `$TMP-reviewer-id`; do not spawn another; drive rounds 2–3 by `SendMessage` to it.

### The reviewer (single mode round 1; both modes rounds 2–3)

Spawn a **single** `general-purpose` reviewer and keep that same agent across all rounds via `SendMessage` — its context and prior findings preserved; a real dialogue, not three fresh reviews. **The moment you spawn (or re-spawn) any reviewer, write its agent id/name to `$TMP-reviewer-id`, overwriting** — that single-line file always holds the *current live* reviewer's handle; re-read it whenever a context drop loses the in-memory one. **After each round, append to `$TMP-journal.md`:** the reviewer's findings, your fix/rebuttal for each, and the `STATUS:` line — the durable transcript recovery reconstructs from.

If the reviewer can't be resumed, dies, or round 1 ends with no parseable `STATUS:` line, recover per `recovery.md` § Reviewer recovery. **Never treat an absent `STATUS:` as `CONVERGED`, and never let the loop silently degrade into three context-free reviews.**

**Round-1 reviewer context** (to the single reviewer; in panel mode, to each panelist and the post-merge reviewer per `panel.md`):
- The original requirement and the `$AC` checklist **verbatim** (from `$TMP-requirement.md` / `$TMP-ac.md`).
- The implementation summary, plus `$BASE` and the exclusion list so it pulls **the scoped diff** exactly as you do (hand over the recipe per that section — both halves). Instruct it to actually explore the surrounding code rather than reviewing the pasted diff in isolation, and to run the *specific* tests it scrutinizes — it has the tools — but **not** the full suite: the Phase-1 handoff already pasted a green full-suite run and the final gate re-runs it; a third full run buys nothing.
- Act as an adversarial code reviewer: correctness bugs, missed requirements, missing/weak test coverage, edge cases, design problems. Return a numbered list of findings, each with severity (blocker / should-fix / nit) and concrete rationale.
- **Evidence gate (every blocker and should-fix):** cite a specific `file:line` AND carry proof — *either* a failing test the reviewer actually wrote and ran (pasted with its failure output) *or* exact reproduction steps (commands + observed vs. expected). Without a repro, demote to `nit` labeled "unverified — could not reproduce." **Batch the evidence tests:** collect them into one scratch file and run them in a single pass (one run, one delete), not a write-run-delete cycle per finding. **Light tier:** repro steps only — no evidence tests written at all. The same skeptic's burden the loop applies to you: no plausible-but-unproven blockers.
- **Leave the tree as found:** an evidence test is by definition *failing* and would ride into the deliverable diff or redden your final gate on a test you never authored. The reviewer pastes evidence into its report, then deletes every scratch/evidence test and reverts every bite break, and confirms the scoped diff — both halves, so a leftover *untracked* scratch file is caught too — is back to implementation-only before responding (recorded pre-existing paths are expected to remain and don't count).
- **Acceptance-criteria pass:** walk `$AC` and mark each criterion met / unmet / untested-but-met / pending human visual check (the last for presentational criteria — cite the implementing code location for me to eyeball, never assert "met"), citing where each is satisfied. Any unmet criterion is at least a `should-fix` (a blocker if core to the requirement). *(Panel mode: this is the requirements-coverage lens's job; other panelists skip it.)* **AC-completeness check (autonomous):** `$AC` was adopted without a human re-confirming it, so the reviewer must also audit it for *completeness* against the requirement/plan (`## What to build` + the parent plan doc, if provided): a material behavior with no corresponding criterion → `should-fix` ("AC gap: <behavior> uncovered"). This closes the hole where a missing criterion can never be flagged because nothing in `$AC` names it.
- **Test-bite audit** *(single reviewer only — in panel mode this runs serially after the merge, per `panel.md`)*: independently pick 2–3 of the most important tests, deliberately break the covered code, confirm the test fails, revert (revert-safe, per Phase 1). A test green against broken behavior → `blocker` ("test does not bite"). Tell it which tests never had a red phase (from the handoff record) so it prioritizes those (only one test exists → it bites that one). **Light tier: skip this audit entirely.** Zero-test case → the audit is N/A; verify `$AC` by hand instead of inventing tests.
- The **frontend scoping rule** from Phase 1: trivial/presentational frontend code is intentionally untested — not a "missing coverage" finding; only genuinely non-trivial untested frontend logic may be flagged. Backend/business-logic coverage is fair game as usual.
- **End every response with a status line:** `STATUS: CONVERGED` or `STATUS: OPEN — blockers:N should-fix:M nits:K ac-unmet:U bite-failures:B`, so the loop is machine-checkable. *(Panel mode: panelists must NOT emit `STATUS:` — drop this bullet for them; only the post-merge reviewer judges convergence.)*

### Convergence

`STATUS: CONVERGED` is **illegal** while any of these hold: an open blocker or should-fix, an unmet `$AC` criterion, or a test that failed the bite audit. `CONVERGED` means every blocker and should-fix is **resolved**, every criterion is met or marked "pending human visual check" (none left unmet), and all audited tests bite. **"Pending human visual check" does NOT count as unmet** — it defers to Phase 3's human verification; otherwise a clean all-presentational (zero-test) change could never legally converge and would burn every round. (Confirm such criteria are *implemented and ready to be eyeballed*, not "met.") A finding is **resolved** when fixed *or* its rebuttal is accepted by the reviewer — a conceded rebuttal is a valid resolution. Open `nit`s don't block.

**On `CONVERGED`, reconcile before accepting:** every should-fix/blocker you rebutted (rather than fixed) must have been affirmatively **conceded by the reviewer in writing**, not silently dropped — anything not conceded is still open; `SendMessage` for an explicit concede-or-push-back before exiting. **Panel mode:** also confirm the reviewer adjudicated every `recheck` nit from `$TMP-merged-r1.md` — re-promoted, or explicitly could-not-reproduce. An unmentioned `recheck` nit blocks acceptance: `SendMessage` to adjudicate it, so a real bug a panelist under-documented can't slip out as a silently-ignored nit.

### Evaluating findings

You evaluate each finding on its merits — never reflexively agree:
- **Agree** → apply the fix (TDD style: test first where it makes sense), note "fixed: <finding>".
- **Disagree** → a specific rebuttal: why it's wrong, out of scope, or already handled. Against an evidence-backed finding, address the repro directly (why it's invalid, or why the behavior is correct).
- **Blockers are special:** never silently rebut a `blocker`. Fix it, or — if you genuinely believe it's wrong — escalate for adjudication (`BLOCKED:{contested_blocker}` with both sides' reasoning). Never self-resolve a contested blocker.

**Rounds 2 and 3 (round 3 interactive-only):** `SendMessage` the same reviewer: which findings you fixed (and how), your rebuttals with reasoning, and the list of files/tests your fixes touched. **These rounds are fix-verification, not re-review:** the reviewer re-examines only the fix diff and runs only the touched tests — no full-suite run (the final gate owns that), no re-pull or re-review of the unchanged remainder. It responds to your rebuttals (concede or push back with new reasoning), re-checks `$AC` criteria your fixes touched, re-runs the bite audit on tests your fixes changed (skip in light tier), raises any new findings your fixes introduced, and emits `STATUS:` again.

**Stopping conditions** (whichever comes first):
- `STATUS: CONVERGED` → run the final green gate, exit the loop.
- **Round cap reached** (2 rounds in autonomous mode, 3 in interactive) → stop regardless; never exceed it. Run the final green gate first (required however the loop stops); then if any blocker or should-fix is still open or contested (the reviewer sustains it and you haven't fixed it — that is not "resolved"), any `$AC` criterion unmet, any bite failure, or (panel mode) any unadjudicated `recheck` nit → escalate (`BLOCKED:{round_cap_open_findings}`), presenting each contested item with both sides' reasoning labeled "contested — implementer-rebutted" so I can make a quick call.

**Final green gate (required before exiting the loop, however it stopped):** later rounds only re-ran touched tests and bites, so a late fix can slip a type or lint error past everything. Re-run the **entire suite + typecheck + lint** — the same gate as the Phase-1 handoff. **Exception — nothing changed:** if the loop converged with zero fixes or edits applied after the Phase-1 handoff gate (re-read `$TMP-journal.md` to confirm — every round's fixes are recorded there; don't trust memory), that gate's green run stands — skip the suite/typecheck/lint re-run and do only the tree check below. Also verify the tree is implementation-only: the scoped diff (recorded pre-existing paths are expected and don't count) must contain nothing from a reviewer scratch test or an un-reverted bite break. Anything red or dirty → fix/clean (TDD style where a test is warranted) and re-run until green; can't within reason → `BLOCKED:{final_gate_red}`, never exit red.

After the loop, summarize for me: the `$AC` checklist with final met/unmet status, what was fixed, what remains contested (both sides' reasoning), and any findings deferred.

## Phase 3 — Self-test guide

Write the guide **yourself** — no subagent. You already hold the requirement, `$AC`, and the final diff in context; a fresh agent would only re-read all of it to produce a disposable file (fresh-context isolation earns its cost for the *reviewer*, not for a how-to-test guide). Re-read `$TMP-ac.md` and `$TMP-plan-path` from disk rather than trusting memory, and write for a human who has **not** seen the diff or this conversation — no run-internal shorthand, every command and path spelled out. The guide is aimed at **me, the human**:
- What changed, in plain terms.
- Exact steps to exercise/verify the change myself (commands, UI flows to click through, data/fixtures, env or config) — organized so each `$AC` criterion has a way for me to check it by hand; for each "pending human visual check" criterion, exactly what to look at.
- What "working" looks like vs. failure signs to watch for.
- Anything risky or worth double-checking that automated tests don't cover.

The guide is a **disposable artifact for me, not part of the deliverable** — keep it out of version control:
- If a plan-doc path **with a doc extension** was provided AND the colocated target would be git-ignored, write it there for convenience — flagging that it's untracked/disposable. Derive the target deterministically: strip the doc extension from `$(basename "$TMP-plan-path")`, append `-test-guide.md`, place in `$(dirname "$TMP-plan-path")` — the stored path is absolute, so this is cwd-independent. Check ignore with `git check-ignore` run from `$TOP` (prints the path and exits 0 when ignored; prints nothing and exits **1** when not ignored — the normal not-ignored case, not a command failure).
- Otherwise (no plan doc, a confirmed source/config file rather than a doc, or the colocated path is not ignored and would land tracked in a versioned dir like `docs/`), write to `$TMP-test-guide.md`, outside the repo. Never default into a tracked dir.

Surface the guide: a human present in this thread gets it printed in the conversation plus the file path. Spawned as a subagent → return **only the path** in your structured result (the full guide would bloat the caller's context; it collects guides at batch end). Either way, never `git add` or commit it.

---

## Structured result (when spawned as a subagent)

When spawned as a subagent (e.g. by `/tdd-review-issues`) rather than driven by a human in-thread, **your final message is your return value** — one structured result, nothing heavy (no pasted guide, no transcript):
```
{ issue:         <the issue path/slug you were given>,
  state:         "DONE" | "BLOCKED",
  ac_outcome:    <one line per $AC criterion: met / unmet / pending-visual — from $TMP-ac.md>,
  end_head_sha:  <git rev-parse HEAD after the final green gate — the tip your work ends at>,
  guide_path:    <the Phase-3 self-test-guide file path>,
  blocked_reason: <the BLOCKED:{reason, detail} string — present ONLY when state is "BLOCKED"> }
```
- `state: "DONE"` only after `STATUS: CONVERGED` (or the round cap with nothing open) **and** a green final gate. Capture `end_head_sha` at that point — the caller asserts the next issue's base against it, so it must be accurate.
- `state: "BLOCKED"` for any genuine-blocker stop: the `BLOCKED:{…}` line in `blocked_reason`, `end_head_sha` = current HEAD, stop without running later phases.
- **On `$BASE`:** the caller spawns you at a specific HEAD and may name it as the base; you also derive your own `$BASE` in git hygiene, and the two coincide because you start at exactly that HEAD. Derive your own as always — but do return `end_head_sha` so the caller can chain the next issue on top.

## After an escalation

**Autonomous:** an escalation *is* a `BLOCKED:{…}` return — stop and return it. A re-spawn after a `BLOCKED` is a **fresh run, not a resume**: pre-flight's `rm -f "$TMP"-*` clears all state, and the reviewer subagent and journal don't survive either, so a true mid-dialogue resume is impossible — the `$TMP-*` files bridge a context summarization *within* a run, not across re-spawns. For the re-spawn to be correct, the caller first rewinds the branch to your `$BASE`, discarding this run's partial commits; the fresh run re-reads its criteria from the issue/plan and rebuilds on a clean base.

**Interactive:** once I reply, act on my directive and resume the phase sequence from where you stopped — run state is on disk under `$TMP-*` (this run's branch name in `$TMP-branch`; `git branch --show-current` as fallback). "Proceed" → finish the gate/loop as instructed and continue to the next phase; "stop" → halt without further phases. An escalation is not a dead end.

---

Throughout: stay in the working directory's existing conventions, keep commits/changes scoped to the requirement, and do not push or open a PR unless I ask.
