export const meta = {
  name: 'implement-issues',
  description: 'Loop through local markdown issues (from /to-issues) in dependency order, implementing each AFK slice test-first; pause at HITL issues.',
  whenToUse: 'After /to-issues has written a directory of issue .md files. Pass the directory as args (default ./issues). Implements AFK slices autonomously, stops at HITL.',
  phases: [
    { title: 'Index', detail: 'Parse issue files into a dependency graph' },
    { title: 'Implement', detail: 'Sequential red-green per issue, commit on green' },
    { title: 'Review', detail: 'Independent review, then implementer adjudicates findings' },
  ],
}

// ---- args ----------------------------------------------------------------
// args may be a string (the issues dir) or { dir }. Default to ./issues.
const issuesDir =
  typeof args === 'string' ? args : (args && args.dir) || './issues'

// Max review<->adjudicate rounds per issue before we stop and ship what we have.
const MAX_REVIEW_ROUNDS = 3

// ---- schemas -------------------------------------------------------------
const INDEX_SCHEMA = {
  type: 'object',
  required: ['issues'],
  properties: {
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'file', 'title', 'type', 'blockedBy'],
        properties: {
          id: { type: 'string', description: 'file basename without .md — stable id' },
          file: { type: 'string', description: 'absolute or repo-relative path to the issue file' },
          title: { type: 'string' },
          type: { type: 'string', enum: ['AFK', 'HITL'] },
          blockedBy: {
            type: 'array',
            items: { type: 'string' },
            description: 'ids (basenames) of issues that must complete first; [] if none',
          },
          done: { type: 'boolean', description: 'true if the file already records this slice as completed' },
        },
      },
    },
  },
}

const RESULT_SCHEMA = {
  type: 'object',
  required: ['status', 'testsPassed', 'notes'],
  properties: {
    status: { type: 'string', enum: ['done', 'failed'] },
    testsPassed: { type: 'boolean' },
    commit: { type: 'string', description: 'short commit sha, or empty if nothing committed' },
    notes: { type: 'string', description: 'one-line summary of what was built or why it failed' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['hasFindings', 'findings'],
  properties: {
    hasFindings: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'detail'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['low', 'medium', 'high'] },
          detail: { type: 'string', description: 'what is wrong and why it matters' },
          location: { type: 'string', description: 'file:line or function, if applicable' },
        },
      },
    },
  },
}

const ADJUDICATION_SCHEMA = {
  type: 'object',
  required: ['decisions', 'fixed', 'testsPassed'],
  properties: {
    decisions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['finding', 'agreed', 'rationale'],
        properties: {
          finding: { type: 'string', description: 'the finding title being decided on' },
          agreed: { type: 'boolean' },
          rationale: { type: 'string', description: 'why you agreed or rejected it' },
          action: { type: 'string', description: 'what you changed, or "ignored"' },
        },
      },
    },
    fixed: { type: 'boolean', description: 'true if any code was changed and committed' },
    testsPassed: { type: 'boolean', description: 'full suite green after any fixes' },
    commit: { type: 'string', description: 'fix commit sha, empty if no fix' },
  },
}

// ---- Phase 1: index ------------------------------------------------------
phase('Index')

const index = await agent(
  `Read every markdown issue file in the directory "${issuesDir}" (glob ${issuesDir}/*.md).
For each file extract:
- id: the file basename without the .md extension
- file: the path you can re-open later
- title: the issue title (first heading, or a "Title:" field)
- type: "AFK" or "HITL" — look for an explicit Type field. If absent, infer: issues that require a human architectural decision, design review, or sign-off are HITL; everything else is AFK.
- blockedBy: read the "## Blocked by" section. Resolve each reference to the *id* (basename) of the issue it points to. "None"/"can start immediately" => [].
- done: true if the file already marks this slice complete (e.g. a Status: done field, or all acceptance-criteria checkboxes ticked); else false.
Return the full list. Do not modify any files.`,
  { label: 'index-issues', phase: 'Index', schema: INDEX_SCHEMA }
)

if (!index || !index.issues || index.issues.length === 0) {
  log(`No issues found in ${issuesDir}. Nothing to do.`)
  return { error: `no issues found in ${issuesDir}` }
}

// ---- topological order (Kahn) -------------------------------------------
const byId = new Map(index.issues.map((i) => [i.id, i]))
const completed = new Set(index.issues.filter((i) => i.done).map((i) => i.id))
const ordered = []
const remaining = index.issues.filter((i) => !i.done)

// Deterministic Kahn: repeatedly take issues whose blockers are all satisfied.
let progress = true
while (remaining.length && progress) {
  progress = false
  for (let k = remaining.length - 1; k >= 0; k--) {
    const iss = remaining[k]
    const unmet = iss.blockedBy.filter((b) => byId.has(b) && !completed.has(b))
    if (unmet.length === 0) {
      ordered.push(iss)
      completed.add(iss.id) // tentatively satisfied for ordering purposes
      remaining.splice(k, 1)
      progress = true
    }
  }
}
// Reset the "real" completion set — `completed` was reused for ordering above.
const reallyDone = new Set(index.issues.filter((i) => i.done).map((i) => i.id))
const cyclic = remaining.map((i) => i.id) // anything left has a dependency cycle / dangling blocker

log(
  `Indexed ${index.issues.length} issues. ${ordered.length} schedulable, ` +
    `${reallyDone.size} already done${cyclic.length ? `, ${cyclic.length} unschedulable (cycle/dangling: ${cyclic.join(', ')})` : ''}.`
)

// ---- Phase 2: implement sequentially ------------------------------------
phase('Implement')

const report = { done: [], skippedHITL: [], blockedSkipped: [], failed: [], cyclic }

for (const iss of ordered) {
  // A blocker may have been skipped/failed — don't implement on a broken base.
  const blockerProblem = iss.blockedBy.find(
    (b) => byId.has(b) && !reallyDone.has(b)
  )
  if (blockerProblem) {
    log(`skip ${iss.id} — blocker ${blockerProblem} did not complete`)
    report.blockedSkipped.push({ id: iss.id, reason: `blocked by ${blockerProblem}` })
    continue
  }

  if (iss.type === 'HITL') {
    log(`pause ${iss.id} — HITL, needs a human decision/review`)
    report.skippedHITL.push({ id: iss.id, title: iss.title, file: iss.file })
    continue // its dependents will fall into blockedSkipped above
  }

  const result = await agent(
    `Implement this issue using strict test-driven development. Work in the current git repository (the one this workflow was launched from) — write source/test files, run tests, and commit there.

ISSUE FILE: ${iss.file}
Read it in full first. It contains "What to build" (the end-to-end behavior of this vertical slice) and "Acceptance criteria" (a checklist).

TDD discipline (follow exactly — do NOT write all tests up front):
1. Pick the first acceptance criterion. Write ONE test for it through the public interface. Run it; confirm it FAILS (red).
2. Write the MINIMAL code to make it pass (green). Run the test.
3. Repeat one criterion at a time. Tests must verify observable behavior, not implementation details.
4. Once all criteria pass, do a small refactor pass (only while green) — extract duplication, keep interfaces small.

Then:
- Discover and run the project's full test command (check package.json / Makefile / pyproject / etc.). All tests must pass.
- If green: stage and commit ONLY the changes for this slice, message "feat(${iss.id}): ${iss.title}". Update ${iss.file} to mark the slice done (tick the acceptance-criteria checkboxes and add/set a "Status: done" line).
- If you cannot get to green, do NOT commit; report status "failed" with the blocking reason.

Use the project's domain vocabulary for test and interface names. Return the structured result.`,
    { label: `impl:${iss.id}`, phase: 'Implement', schema: RESULT_SCHEMA }
  )

  if (result && result.status === 'done' && result.testsPassed) {
    reallyDone.add(iss.id)
    const record = { id: iss.id, commit: result.commit || '', notes: result.notes }

    // --- Review <-> adjudicate loop: re-review after each fix, up to MAX_REVIEW_ROUNDS ---
    const rev = {
      rounds: 0,
      finalClean: false, // reviewer returned no findings on the last pass
      stoppedOn: '', // 'clean' | 'no-fix' | 'max-rounds'
      totalFindings: 0,
      totalAccepted: 0,
      fixCommits: [],
      testsGreen: true,
    }
    let currentCommit = result.commit || 'HEAD' // the latest commit reviewers should inspect

    while (rev.rounds < MAX_REVIEW_ROUNDS) {
      rev.rounds++
      const r = rev.rounds

      const review = await agent(
        `Adversarially review the CURRENT state of this slice. Be skeptical — your job is to FIND problems, not to praise. Default to reporting a concern rather than letting it slide.${r > 1 ? ' This is a re-review: earlier review findings may already have been fixed, so judge the code as it stands now, not the original version.' : ''}

ISSUE FILE: ${iss.file}
Inspect the slice as it currently is (e.g. \`git show ${currentCommit}\` and any follow-up fix commits, plus the working tree and test files). Evaluate:
- Correctness: does it actually satisfy EVERY acceptance criterion? Check edge cases and error paths, not just the happy path.
- Test quality: are tests coupled to implementation details (mocking internal collaborators, asserting private state) instead of observable behavior? Would they survive an internal refactor? Is any criterion left untested?
- Scope: anything built that the issue did not ask for, or any criterion silently skipped.
Report concrete, actionable findings with locations. If the work is genuinely solid, return hasFindings=false with an empty list. Do NOT modify any files — you only review.`,
        { label: `review:${iss.id}#${r}`, phase: 'Review', schema: REVIEW_SCHEMA }
      )

      if (!review || !review.hasFindings || !review.findings.length) {
        rev.finalClean = true
        rev.stoppedOn = 'clean'
        log(`review ${iss.id} round ${r}: clean`)
        break
      }
      rev.totalFindings += review.findings.length

      const adj = await agent(
        `You are the implementer of this issue. An independent reviewer raised the findings below. For EACH finding, decide whether you agree — think it through on the merits.
- Agree only when the finding is correct AND worth fixing. You are expected to DISAGREE when the reviewer is wrong or pedantic; explain your reasoning and change NOTHING for that finding.
- For findings you accept: fix the code, keep the full test suite green (re-run it), then commit the fixes with message "fix(${iss.id}): address review".
- Make no change for findings you reject.

ISSUE FILE: ${iss.file}
COMMIT UNDER REVIEW: ${currentCommit}
REVIEWER FINDINGS:
${review.findings
  .map((f, n) => `${n + 1}. [${f.severity || 'n/a'}] ${f.title} — ${f.detail}${f.location ? ` (${f.location})` : ''}`)
  .join('\n')}

Return a decision for every finding, whether you committed a fix, and whether tests are green afterward.`,
        { label: `adjudicate:${iss.id}#${r}`, phase: 'Review', schema: ADJUDICATION_SCHEMA }
      )

      const accepted = adj ? adj.decisions.filter((d) => d.agreed).length : 0
      rev.totalAccepted += accepted
      const fixed = !!(adj && adj.fixed)
      if (fixed) {
        if (adj.commit) {
          rev.fixCommits.push(adj.commit)
          currentCommit = adj.commit // next re-review inspects the fixed state
        }
        rev.testsGreen = adj.testsPassed
      }
      log(
        `review ${iss.id} round ${r}: ${review.findings.length} findings, ${accepted} accepted` +
          (fixed ? `, fixed (${adj.commit || 'uncommitted'})` : ', no fix') +
          (fixed && !adj.testsPassed ? ' — WARNING: tests not green after fix' : '')
      )

      // Nothing was changed (all findings rejected, or adjudicator failed):
      // a re-review of identical code would just repeat — stop here.
      if (!fixed) {
        rev.stoppedOn = 'no-fix'
        break
      }
      // A fix landed. Loop to re-review unless we've hit the cap.
      if (rev.rounds >= MAX_REVIEW_ROUNDS) {
        rev.stoppedOn = 'max-rounds'
        log(`review ${iss.id}: reached max ${MAX_REVIEW_ROUNDS} rounds — shipping with possible open findings`)
      }
    }

    record.review = rev
    report.done.push(record)
    log(`done ${iss.id}${result.commit ? ` (${result.commit})` : ''}`)
  } else {
    report.failed.push({ id: iss.id, notes: result ? result.notes : 'agent returned no result' })
    log(`FAILED ${iss.id} — dependents will be skipped`)
    // Do not add to reallyDone → dependents auto-fall into blockedSkipped.
  }
}

// ---- summary -------------------------------------------------------------
log(
  `Finished: ${report.done.length} done, ${report.skippedHITL.length} HITL paused, ` +
    `${report.blockedSkipped.length} skipped (blocked), ${report.failed.length} failed.`
)
return report
