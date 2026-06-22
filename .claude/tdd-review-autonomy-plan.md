# Plan: Autonomous handoff + light orchestrator for the `tdd-review-issues` stack

Status: **IMPLEMENTED** (2026-06-22) across all three files, then adversarially coherence-checked and patched. Decisions taken: both skills autonomous-by-default with an `--interactive`/`--afk`/`--autonomous` flag; defensive machinery kept except the cut items below; `/tdd` autonomy added in `tdd/SKILL.md`. Changes are in the dotfiles canonical copies only — **re-sync `~/.claude/skills/...` and `~/.claude/commands/...` yourself**, and nothing was committed.

Post-implementation coherence fixes applied (caught by a verifier pass): added the explicit subagent **structured-result schema** to `tdd-review-loop.md` (the orchestrator's `end_head_sha`/`ac_outcome`/`state`/`guide_path` consumers had no producer); named `BLOCKED:{…}` tokens on the four genuine-blocker escalation gates; made the tip-assertion skip the legitimate **resume of a PAUSED issue** (was a false-positive stall); made the interactive-issue path run **in-thread** rather than as a hang-prone subagent; taught the loop to parse `--afk`/`--autonomous` (the orchestrator invokes with `--afk`).

The original proposal follows, for reference.

Scope: `tdd-review-issues/SKILL.md`, `commands/tdd-review-loop.md`, `tdd/SKILL.md`.
(These are the dotfiles canonical copies; `~/.claude/skills/...` are non-symlink copies and must be re-synced after edits.)

---

## 0. Goals & decisions (your answers)

1. **Both** `tdd-review-issues` *and* `tdd-review-loop` are **autonomous by default**. Changing the
   default behavior of the underlying `tdd-review-loop` command is in scope. An `--interactive`
   escape hatch is kept for when a human deliberately wants the old gate-by-gate experience.
2. **Keep** the defensive machinery — *as long as it works without your input*. Only convert gates
   that require **human input** into autonomous decisions, and only **cut** machinery that is
   genuinely **harmful or not useful**.
3. `/tdd`'s planning autonomy lives **in `tdd/SKILL.md`** (so `/tdd` itself becomes AFK-capable for
   any caller), not bypassed from the loop.
4. **Light orchestrator** via subagent delegation (see §2).

### The one realization driving everything

Complaints #1 (too many questions) and #2 (orchestrator context rot) are **one architectural
problem with one fix**. A Task subagent can't prompt a human — so today's interactive loop can't be
delegated. But once the loop **proceeds autonomously from the documentation and only *returns*
`BLOCKED` on genuine blockers**, it has no human gates, which makes it safe to run headless inside a
subagent — and *that* is what keeps the orchestrator's context tiny. Autonomy is the precondition;
delegation is the payoff.

---

## 1. Autonomous mode — the contract (applies to both skills)

Default behavior flips from *"halt at the first gate"* to:

> **Decide from the documentation and announce-and-proceed. If a decision is genuinely
> undecidable-from-docs or unsafe, do not invent a default — surface a structured `BLOCKED:{reason}`
> and stop.** Whether "surface" means *prompt the human in-thread* (standalone run, human present)
> or *return to the caller* (run as a subagent under the orchestrator) is determined by context, not
> by the skill — the skill just emits the blocker and stops.

Model every converted gate on the loop's **existing** announce-and-proceed pattern
(`tdd-review-loop.md:122`: *"state in one line… then proceed. Don't stop to ask; I'll override if I
disagree"*). That phrasing is already the template — we're generalizing it.

`--interactive` restores the current gate-by-gate behavior verbatim (the existing prose becomes the
`--interactive` branch; autonomous becomes the default branch).

### Gate-conversion table (what each gate reads to decide; what still stops you)

| Gate (today) | File:line | Autonomous behavior | Reads to decide | Residual hard-stop → `BLOCKED` |
|---|---|---|---|---|
| Phase 0 AC approval loop | `loop.md:88-90` | Adopt the requirement's `## Acceptance criteria` **verbatim** as `$AC` if present; else distill + **announce** (don't wait). Persist `$TMP-ac.md`. | issue's `## Acceptance criteria` (human-approved when `/to-issues` wrote it) | section absent/empty **and** can't form coherent AC; or AC **materially contradicts** `## What to build` → `ac_missing` / `ac_contradicts` |
| `/tdd` interface confirm | `tdd/SKILL.md:51,58`; `loop.md:96,100` | Derive interface from `## What to build` + `## Parent` plan + repo conventions; announce | issue, plan doc, existing code | two *materially different* signatures both satisfy AC, **or** sensitive surface (auth/payments/migrations/PII) → `interface_underdetermined` / `sensitive_surface` |
| `/tdd` behaviors-to-test | `tdd/SKILL.md:52,56,60`; `loop.md:98` | Auto = testable subset of `$AC`, frontend-scoping rule applied mechanically; announce | `$AC` + frontend rule | money/validation/data-integrity borderline only → `test_scope_borderline` |
| Orchestrator run-plan approval | `SKILL.md:99-105` | Compute DAG order + HITL/AFK classes + branch slug; announce | `## Blocked by` (authoritative), `**Type**`, parent-plan slug | DAG cycle, missing/ambiguous `**Type**`, dangling blocker |
| Orchestrator dirty-tree | `SKILL.md:113-124`; `loop.md:54-65` | If only **in-set** issue/plan files are dirty → commit them (the stated default), announce | membership in parsed issue+plan set | any **out-of-set** path dirty → `dirty_out_of_set` |

### Residual hard-stops (the only things that reach you)

These keep their current escalation logic; in autonomous mode they **return `BLOCKED`** instead of
prompting:

- Phase-1 stuck (~3 failed green attempts / no progress) — `loop.md:102`
- Contested blocker (implementer-vs-reviewer standoff) — `loop.md:191`
- 3-round cap with findings still open/contested — `loop.md:201`
- Red final green gate (suite/typecheck/lint won't go green) — `loop.md:203`
- AC missing-or-contradictory; interface underdetermined/sensitive; out-of-set dirty tree (above)
- Orchestrator structural: DAG cycle, ambiguous `**Type**`, dangling blocker, blocker-not-DONE
- **HITL issues** — never delegated, never autonomous (by definition)
- **Inconsistent on-disk state on resume** — return `BLOCKED:{inconsistent_state}` (see §4)

---

## 2. Context fix — delegate each AFK issue to a subagent

**Mechanism of the bloat (confirmed):** `tdd-review-loop` is a **slash command**, so its
~25–30K-token body expands *inline* into the orchestrator on every AFK issue (`SKILL.md:157`), and
all of that issue's execution (every `/tdd` red→green cycle, bite-check churn, green-gate suite
output, relayed reviewer round-trips — `loop.md:10`, `SKILL.md:160`) lands in the *same* context
because the orchestrator **is** the implementer. ≈50–90K tokens/issue → 2 issues ≈ 27%.

**Fix:** in the orchestrator's AFK branch (`SKILL.md:157-172`), stop invoking `/tdd-review-loop`
inline. Instead **spawn one `general-purpose` Task subagent per AFK issue**, hand it
`{issue path, $BASE = current HEAD, branch name, exclusion list, panel pref}`, tell it to run the
loop in autonomous mode, and have it **return only**:

```
{ issue, state: DONE | BLOCKED, ac_outcome, end_head_sha, guide_path, blocked_reason? }
```

The 25–30K body + all narration now live in the **subagent's** context and are discarded on return.
The orchestrator accumulates ~1 result object + 1 ledger line per issue. This composes with the
orchestrator's existing on-disk state (`$WTMP-progress.md`, `$WTMP-set.md`, `$WTMP-branch`;
`SKILL.md:36-50, 174-196`) — the final summary is already rebuilt from disk (`:200-208`), so the
narration was always disposable.

**Two constraints to write in explicitly (verifier-flagged, currently unstated):**

- **Strictly sequential.** AFK subagents share one working tree and one deterministic `$TMP` prefix
  (`loop.md:20`). Never run two concurrently — they'd collide on the tree and `/tmp` state. Add as a
  hard precondition in the orchestrator.
- **One upfront human checkpoint is unavoidable.** Issue 01 is the sole HITL and is the `## Blocked
  by` of issue 02. So a correct run *opens* by pausing in-thread for you to resolve 01, then runs
  02–07 autonomously. Frame the UX as "one upfront design checkpoint, then hands-off," not "zero
  questions."

---

## 3. Per-file edit plan

### `commands/tdd-review-loop.md`

- **Header (`:6-12`):** replace the "interactive, halts at first gate" framing with the §1 contract
  as the **default**, and add: "`--interactive` restores per-gate prompting." Keep the
  halt-rather-than-invent-a-default principle, but redirect it from *prompt* to *emit `BLOCKED` and
  stop*.
- **Parse `$ARGUMENTS` (`:36`):** recognize `--interactive` as a leading/trailing flag using the
  *exact* same first/last-token, ASCII-literal, mid-text-is-prose discipline already specified for
  `--panel`. Persist with the same sentinel pattern (`$TMP-interactive-flag`).
- **Phase 0 (`:88-90`):** add the autonomous branch from the table — adopt provided `## Acceptance
  criteria` verbatim, else distill+announce; `BLOCKED` only on missing+incoherent or contradictory.
  Keep the confirm-loop under `--interactive`.
- **Phase 1 (`:96-100`):** the interface/behaviors checkpoints become announce-and-proceed in
  autonomous mode; `BLOCKED` per the table. (The actual gate text lives in `tdd/SKILL.md` — this
  file must **pass the autonomous signal through** to `/tdd`; see that file's edit.)
- **Frontend scoping (`:98`):** add the mechanical autonomous default (">1 branch or any data
  derivation → extract+test; else skip; announce; `BLOCKED` only on money/validation/integrity
  borderline").
- **Pre-run hygiene (`:54-65`):** dirty-tree/branch gates **return `BLOCKED`** in autonomous mode
  rather than prompt. **Do not touch the NUL-safe exclusion builder logic** (it works without input
  — keep per your principle).
- **Escalations (`:102, :173, :191, :201, :203`):** autonomous mode **returns**
  `BLOCKED:{stuck_phase1 | no_status | contested_blocker | round_cap | red_gate}` — same conditions,
  return instead of prompt.
- **Phase 3 guide (`:207-219`):** when running as a subagent, **write the guide to a file and return
  only its path** — do **not** print it inline (`:219`). (Keeps 6 guides out of the orchestrator
  context.)
- **Do NOT touch:** the entire Phase-2 review engine (evidence gate, bite audit,
  illegal-convergence, `recheck` re-promotion, convergence reconciliation), `$BASE`/exclusion-diff
  mechanics, the persisted-state design.

### `tdd-review-issues/SKILL.md`

- **Header / `:16-22`:** replace "interactive by design, halt at first gate" with the **two-tier**
  contract: HITL in-thread; AFK delegated + autonomous; the human is reached via relayed `BLOCKED`
  results and HITL pauses, not per-gate prompts. Add `--interactive` passthrough note.
- **AFK branch `:157-172` (core change):** stop invoking `/tdd-review-loop` inline; **spawn one
  subagent per AFK issue** per §2; on `DONE` write the ledger line + record `guide_path`; on
  `BLOCKED` relay to the human, mark PAUSED, do **not** auto-advance (`:170-172` semantics
  preserved). Delete "relaying every one of its gates to me" (`:160`) — there are no per-gate relays
  anymore.
- **`:161-163`:** delete "(it will still ask me to confirm — that's fine)"; replace with "autonomous
  mode adopts the issue's `## Acceptance criteria` verbatim, no confirm."
- **Run-plan gate `:99-105` / dirty-tree `:113-124`:** apply the table (announce-and-proceed;
  auto-commit in-set files; `BLOCKED` on structural/out-of-set).
- **Sequential precondition + upfront-HITL note** (§2) added near the main loop.
- **Ledger `:174-181`:** add `tip:<end_head_sha>` to each DONE entry → enables the clean-tip
  assertion in §4.
- **Do NOT touch:** `$WTMP` derivation/resumability (`:36-50, 187-196`), the DAG logic, the
  final-summary-from-disk design (`:200-208`).

### `tdd/SKILL.md`

- Add a short **"Autonomous mode"** note: "When the caller signals autonomous mode, derive the
  public interface and the behaviors-to-test from the provided acceptance criteria + plan doc + repo
  conventions and **announce-and-proceed** at the Planning checklist (`:45-60`) instead of asking;
  reserve a stop only for a genuinely undetermined or sensitive interface." This makes `/tdd`
  AFK-capable for any caller (your choice) and is what lets `loop.md` Phase 1 run headless.
- **Do NOT touch:** the red-green-refactor loop, the horizontal-slice anti-pattern, the
  one-test-at-a-time rules — the heart of the value.

---

## 4. Correctness fixes folded in (verified)

- **PAUSED/SKIPPED commit leak (confirmed).** Each loop captures `$BASE = HEAD` at the
  already-advanced HEAD (`SKILL.md:134`); a PAUSED or SKIPPED issue may have left partial `/tdd`
  commits on the shared branch (`loop.md:106`) that then get attributed to the *next* issue's
  `$BASE` diff. Fix: before spawning issue N's subagent, assert `current HEAD == prior DONE issue's
  recorded `tip` sha`. On mismatch (a non-DONE issue left commits), **stop** — don't silently fold
  them into N's diff. This is why §3 adds `tip:` to the ledger.
- **Resume-state catch-all.** When collapsing/keeping the sentinel-recovery web, the autonomous
  catch-all must be `BLOCKED:{inconsistent_state}`, **never** "stop and ask" (that would
  reintroduce the gate we're removing).

> Not folded in (unverified, likely overclaims by the correctness lens): a "shasum collision" risk
> on the 12-char `$TMP` hash and an exit-code nit in the bare-repo check. I'll sanity-check these
> during implementation and only touch them if real.

---

## 5. Proportionality — apply your "keep if it works without my input" rule

| Machinery | Works without your input? | Decision |
|---|---|---|
| Sentinel-recovery web (`loop.md:40,43,46,48`) | Yes (autonomous crash recovery) | **Keep** — but route its bail-out to `BLOCKED:{inconsistent_state}`, not a prompt |
| NUL-safe exclusion builder (`loop.md:54-64`) | Yes | **Keep** |
| Worktree-reclaim sweeps (`loop.md:32,134,139`) | Yes | **Keep** (only relevant if the opt-in panel path stays — see below) |
| `$TMP` file-inventory paragraph (`loop.md:26`) | Yes | **Keep** |
| Reviewer panel + heuristic (`loop.md:120`) | Yes (no human input) | **Keep** — per your rule, don't default it off |
| **Opt-in per-panelist worktree path** (`loop.md:131-137`) | Yes, but **not useful** (non-default; file itself marks static panel as full-coverage; ~700 tokens of git choreography run up to 3×; highest-risk block) | **Cut candidate** — flagged under "not that useful." Your call in §7. |
| **"Record excluded paths" dirty-tree branch** (`SKILL.md:119-121`) | Yes, but **mildly harmful** (stale-list hazard if a HITL issue edits downstream issue files mid-run) | **Cut** — "commit in-set files" is already the default and avoids the hazard |
| Phase-3 guide printed inline per issue (`loop.md:219`) | Yes, but bloats orchestrator context | **Relocate, don't delete** — write to file, return path (§3) |

Net: we **keep almost everything** and only cut the two items that fail the "harmful or not useful"
test. The big context win comes from the subagent boundary (§2), not from deleting machinery.

---

## 6. What this does NOT change

- The adversarial review engine and its convergence rules.
- The TDD red-green-refactor core.
- `$BASE`-per-issue diff isolation and the single stacked branch.
- The orchestrator's on-disk ledger/resumability design (we extend it with `tip:`, not rewrite it).

---

## 7. Open items for you to confirm before I implement

1. **Cut the opt-in per-panelist-worktree path?** It's the one piece that's "not that useful" and
   the riskiest block. Recommend cutting; say keep if you want concurrent panelist suite runs.
2. **`--interactive` granularity:** one global flag that restores *all* old gates (simplest), or per
   the gate-conversion table you might want a couple gates (e.g. sensitive-surface interface) to stay
   blocking even in autonomous mode regardless? Recommend: single global flag + the fixed residual
   hard-stops in §1 (no per-gate knobs).
3. **AC completeness check:** adopt issue AC verbatim *and* have the post-merge reviewer audit it for
   completeness against `## What to build` (closes the "reviewer can't catch a criterion that was
   never in `$AC`" hole, costs nothing on the happy path)? Recommend yes.
4. **Sync:** after I edit the dotfiles canonical copies, do you want me to also copy them into
   `~/.claude/skills/...` and `~/.claude/commands/...`, or do you run your own dotfiles sync?
