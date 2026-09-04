# Adversarial review brief — architecture map

You are reviewing an architecture document that claims to describe this repository. Assume it is wrong until the code proves otherwise. Find every place it misleads a reader, and prove each one with a `path:line` in the repo.

You may read anything in the repository. You may not edit anything except your findings file. **You may not spawn subagents or delegate**: do the checking yourself, within a budget of about **80 tool calls**. Use `grep -n` and `sed -n A,Bp`; never print whole files.

## What to check

Your assignment names a **scope**: either a full round (with a row sample) or a diff-only round.

- **Full round.** Check every row in §2 Subsystems and §4 Data stores. In §3 Edges check every third row, starting at the row number your assignment gives (reviewer A starts at 1, reviewer B at 2), so the two reviewers together cover two thirds. Then spend the rest of the budget hunting for what the document **omits**.
- **Diff-only round.** Check only the rows that appear in the diff file your assignment names, then hunt for omissions the previous round's fixes may have introduced.

For each row you check, open the cited evidence and confirm it says what the row claims. Then look at what the row leaves out.

1. **Phantom** — a subsystem, edge, store, or service the code does not contain, or the cited line does not show it.
2. **Missing** — a deployable unit, seam, store, or external service that exists in the code and is absent from the map. Check workspace manifests, Dockerfiles, deploy manifests, queue/topic names, connection strings, SDK clients, cross-package imports.
3. **Wrong mechanism or direction** — the edge exists but not as described.
4. **Wrong ownership** — a store attributed to the wrong subsystem, or a reader listed as a writer.
5. **Stale** — the cited evidence exists but the surrounding code has moved on.
6. **Unsupported prose** — a sentence outside the tables asserting an architectural fact without a row backing it.

Not findings: rows in §7 (already conceded, unless you can *resolve* one with evidence); the Mermaid block and diagram (generated from the tables); wording, formatting, cell length; exact counts (replicas, template totals) — the map deliberately omits them.

## Output format

Write exactly this structure. One finding per block. Number ids sequentially.

```
# Findings — <reviewer name> — round <N>

Reviewed: <path> @ <git rev-parse --short HEAD>
Claims checked: <count of rows you opened evidence for>

## F1 — <severity> — <category>
Row: <row id from the map, or "prose §N">
Claim: "<quote the cell or sentence verbatim>"
Evidence: <path:line> — <what the code actually shows, one or two sentences>
Fix: <the exact cell edit, row addition, or row deletion, in the survey-table column names>
```

Severity: `wrong` (a reader acting on this would be misled), `missing` (a reader would not know this exists), `stale` (true once, not now). Category: one of the six attack headings.

If you found nothing, write the header, the counts, and the single line `No findings.` A short findings file with proven items beats a long one with guesses; a finding without a `path:line` will be discarded.
