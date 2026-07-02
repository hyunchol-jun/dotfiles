# Panel mode — Phase 2, round 1 only

Read this only when the round-1 mode decision in `SKILL.md` chose the panel. Everything here inherits `SKILL.md`'s definitions: the scoped diff, the durable-state discipline, `$AC`, the round-1 reviewer context block, the zero-test case.

## Spawn

**First capture the Phase-1-handoff HEAD:** `$PRE_SNAPSHOT = git rev-parse HEAD`, persisted to `$TMP-pre-snapshot.sha`, **before spawning any panelist** — teardown asserts HEAD against it to catch a rogue panelist commit. (`$BASE` won't do: HEAD ≠ `$BASE` after `/tdd`'s commits. The panel makes no commit, but the assert still needs a reference.)

Spawn 3–4 `general-purpose` reviewers in parallel (single message, multiple tool calls). **Default to all 4 lenses.** Drop to 3 — folding edge-cases into correctness — only when the diff is panel-worthy purely on the high-risk disjunct, OR is just over a single size threshold: <5 files AND <250 changed lines AND no concurrency/async/ordering/partial-failure surface. Real concurrency surface keeps its dedicated lens regardless of size.

Each panelist gets the same round-1 reviewer context (requirement, `$AC`, `$BASE` + exclusion list, implementation summary, frontend scoping rule) with three changes:

1. **A distinct lens, findings confined to it:**
   - **correctness** — logic bugs, wrong outputs, broken control flow, mishandled return values.
   - **edge-cases / concurrency** — boundaries, nulls/empties, error paths, races, ordering, partial failures.
   - **requirements-coverage** — walk `$AC`; find criteria unmet, partially met, or untested (this lens owns the acceptance-criteria pass; other panelists skip it).
   - **test-quality** — by inspection only: weak, tautological, or non-biting tests and untested logic; **nominate** the 2–3 tests most worth a bite audit (don't run it — that's the post-merge reviewer's, serially). Zero-test case: confirm no tests were warranted — nothing to nominate is expected, not a finding — but still flag genuinely non-trivial logic left untested per the frontend scoping rule.
2. **It is read-only** — read and report; never edit or mutate the tree.
3. **It must NOT emit a `STATUS:` line** — only the post-merge reviewer judges convergence.

**Read-only evidence gate (replaces the write-and-run gate):** panelists don't write and run repro tests, so don't hold them to the failing-test evidence bar. Instead every panel finding cites a specific `file:line` plus precise **observed-vs-expected reasoning** (what the code does on what input vs. what it should do). Panel findings are **provisional**: the post-merge reviewer converts survivors into evidence-backed findings before convergence is judged — a real bug is never demoted to `nit` merely for lacking a written repro.

**Shared-tree caveat:** the panel shares one working tree with no harness-level write lock — "read-only" is an instruction a panelist may still violate — and concurrent suite runs collide on non-namespaced artifacts (`.pytest_cache`, coverage files, `__pycache__`, snapshots, `dist`/`build`/`target`, test DBs, fixed ports), producing flaky failures a panelist would misreport as real findings. So at most **one** panelist runs the suite; tell the others explicitly **not** to — they review statically, against the green suite output captured at the Phase-1 handoff. The read-only evidence gate means this does not cap their severity.

## Teardown — run on every exit path

Whether panelists returned normally, one errored/aborted, or you stopped:
1. Confirm via `git status --porcelain` and the scoped diff that the tree still matches the Phase-1 handoff; `git checkout`/`git stash -u` away any stray panelist change.
2. **Assert HEAD == `$PRE_SNAPSHOT`** (re-read `$TMP-pre-snapshot.sha`) — a rogue panelist *commit* is invisible to the porcelain/diff checks. HEAD moved → `BLOCKED:{rogue_panelist_commit}` (autonomous) or stop and tell me (interactive).

Panelists are discarded after round 1 — never try to resume them.

## Merge

Merge the panel's findings into one numbered list:
- Collapse entries only when they describe the **same defect / root cause** (not merely the same `file:line`), keeping the highest severity and strongest evidence.
- A blocker/should-fix that fails the read-only evidence gate (no `file:line`, *or* no observed-vs-expected reasoning) demotes to `nit` tagged **`recheck`**. A `recheck` nit is not silently ignored: the post-merge reviewer must independently re-investigate every one before its first `STATUS:` and re-promote any it reproduces.
- Carry the test-quality lens's bite-audit nominations forward separately.
- **Persist the merged list to `$TMP-merged-r1.md` — even if empty** (it's the round-1 reconstruction source if the post-merge reviewer dies).

## Post-merge reviewer

Spawn **one** `general-purpose` reviewer — **always, even on an empty merged list**: it is the only source of the round-1 `STATUS:` line, and without one a clean diff can't exit early. Write its id to `$TMP-reviewer-id` the moment you spawn it (`SKILL.md`'s overwrite rule). Hand it the **full round-1 reviewer context block** plus the merged list as the round-1 findings — it owns the `$AC` pass and the convergence judgement from here; don't leave it to re-derive that context. With the tree to itself it must:
- Convert the panel's provisional findings into evidence-backed ones under the real evidence gate.
- Independently re-investigate every `recheck` nit and re-promote any it reproduces.
- Run the **bite audit serially** on the nominated tests (plus any others it judges important): break the covered code, confirm the test fails, revert — revert-safe per Phase 1. A test green against broken behavior → `blocker` ("test does not bite"). Zero-test case → the audit is N/A; verify `$AC` by hand.
- **Emit the `STATUS:` line in its first response**, covering the merged list plus its audit results.

It then **is** the single reviewer for rounds 2–3 — return to `SKILL.md` and drive the dialogue by `SendMessage`.
