---
name: map-architecture
description: Map a repo's architecture — subsystems, the edges between them, data stores — into an evidence-backed markdown doc, harden it through adversarial review (Claude subagent + GPT via omp), then render an editable diagram. Incremental by default — re-surveys only units touched since the last map.
disable-model-invocation: true
---

You are a cartographer. You survey the repo, assemble the map from the survey files with a script, let two hostile reviewers attack it, then publish. The map is only as good as its **evidence**: every row cites `path:line`. Anything without evidence is `unverified`, never stated as fact.

**Token discipline is part of the job.** The main context holds counts and rulings, never tables. Tables live on disk and are moved by scripts. Subagents write files and reply with one line. You never retype a table a subagent already wrote.

Task text (may be empty):

$ARGUMENTS

## Parse `$ARGUMENTS`

Flags may appear anywhere; strip each one you honor. Remaining text is a focus hint; empty means the whole repo.

| Flag | Default | Meaning |
|---|---|---|
| `--out <dir>` | `docs-local/architecture` | output directory, relative to the repo toplevel |
| `--full` | off | ignore an existing map and re-survey everything |
| `--rounds <n>` | `1` | adversarial review rounds |
| `--diagram <fmt>` | `excalidraw` | one or more of `excalidraw`, `tldraw`, `html`, comma-separated (e.g. `--diagram excalidraw,html`). `excalidraw` and `html` use bundled scripts; `tldraw` invokes that skill |
| `--gpt-model <m>` | `openai-codex/gpt-5.6-sol` | passed as `omp --model <m>` |
| `--gpt-effort <e>` | `xhigh` | passed as `omp --thinking <e>` |
| `--gpt-runner <r>` | `omp` | `omp` or `codex` (fallback when omp is not logged in) |

Announce the resolved config in one line: `mode: full|incremental · out: <dir> · rounds: N · diagram: <fmt> · gpt: <runner> <model> @ <effort>`.

`SKILL_DIR` is this skill's base directory (announced when the skill loaded). Scripts: `$SKILL_DIR/scripts/{assemble.py,changed_units.py,gen_excalidraw.py,gen_html.py}`. Briefs: `SURVEY-BRIEF.md`, `REVIEWER-BRIEF.md`.

## Pre-flight

1. GPT runner. For `omp`: `command -v omp` and `omp usage` — a "No credentials found" line means the user must run `omp` interactively once and `/login` with the OpenAI Codex account; stop and tell them (or rerun with `--gpt-runner codex`). For `codex`: `command -v codex`, and `codex login` if unauthenticated. Install nothing yourself.
2. `TOP=$(git rev-parse --show-toplevel)`; `OUT=$TOP/<out>`; `mkdir -p $OUT/survey $OUT/reviews`. Run `git check-ignore -q $OUT`; if tracked, say so in the final report.
3. Mode. `$OUT/ARCHITECTURE.md` exists and `--full` is absent → **incremental**; otherwise **full**.

## Phase 1 — Survey

**Pass 1 — inventory** (full mode, or incremental when `changed_units.py` reports `manifests-changed: yes`). Enumerate deployable and buildable units from the environment, never from memory: workspace manifests, every `Dockerfile`, every deploy manifest (Kubernetes, Helm, Argo WorkflowTemplates, Terraform/Terragrunt, serverless, cron). Use `grep -n`/`find`; never print a manifest in full. Write `$OUT/inventory.md`:

```
| unit | group | paths | manifests | deployed how | evidence |
```

`paths` = comma-separated repo-relative prefixes the unit owns (this is what incremental mode diffs against); `manifests` = the deploy files that reference it; `deployed how` = image / workload / template names with their `path:line`, ≤160 chars. Small packages with a shared deploy story may share one unit. Below the table, an `## Excluded` list: every directory under the workspace roots not in a unit, with a reason (vendored, dead, tooling-only). Also write `$OUT/scope.md`: focus hint, exclusions, and any doc-vs-code contradictions you noticed in existing `docs/**/architecture*`, `README*`, ADRs (these are claims, not truth).

**Pass 1 — incremental.** `cd $TOP && python3 $SKILL_DIR/scripts/changed_units.py $OUT`. It prints the units whose paths changed since the map's commit, unclaimed changed paths, and whether manifests changed. Re-survey only the listed units. Unclaimed paths under a workspace root mean a possibly new unit: add it to the inventory and survey it. Untouched survey files carry forward unchanged. If nothing changed, skip to Phase 5 and report so.

**Pass 2 — edges.** One `general-purpose` subagent per unit to survey, parallel in batches of ≤6. The prompt is: the text of `SURVEY-BRIEF.md`, then `$OUT` and `$OUT/inventory.md` paths, then the unit's inventory row. No `very thorough`; the brief carries a 40-call budget. Each writes `$OUT/survey/<unit>.md` and replies with one line of counts. If a reply contains a table, do not read it — the file is what counts.

**Assemble.** `cd $TOP && python3 $SKILL_DIR/scripts/assemble.py $OUT --sha $(git rev-parse --short HEAD) --repo <name> --focus "<hint>"`. It merges the survey tables, deduplicates seams, assigns stable row ids, generates the Mermaid block, and writes `$OUT/ARCHITECTURE.md`. Read its **stderr warnings** only: dangling names, one pair with several mechanisms, long cells, units with no edges. Fix each by editing the offending survey row (a `sed`/`python` one-liner, or one `general-purpose` subagent if there are more than ~10) and re-run assemble. `ARCHITECTURE.md` is generated — never hand-edit it. Completion: assemble runs with no dangling-name warnings and every unit has an edge or is listed as isolated in `scope.md`.

`cp $OUT/ARCHITECTURE.md $OUT/reviews/ARCHITECTURE.round-0.md` (incremental: also keep the previous map as `reviews/ARCHITECTURE.prev.md` before assembling, and write `reviews/round-1-changed.diff` = `diff -u prev current`).

## Phase 2 — Adversarial review (round N of `--rounds`)

Two reviewers run in parallel on the same file. Both receive `REVIEWER-BRIEF.md` verbatim, the path to `ARCHITECTURE.md`, and a **scope line**:

- Round 1, full mode: `Scope: full round. Reviewer A starts §3 sampling at row 1` (B at row 2).
- Round ≥2, or round 1 in incremental mode: `Scope: diff-only round. Diff: $OUT/reviews/round-N-changed.diff` where the diff is `diff -u reviews/ARCHITECTURE.round-(N-1).md ARCHITECTURE.md` (round 1 incremental: the prev diff from Phase 1).

Neither reviewer sees your reasoning, the survey files, or the other's output.

**Reviewer A — Claude.** Agent tool, `subagent_type: general-purpose`, no `model` param. Prompt: the brief, the path, the scope line, and "write your findings to `$OUT/reviews/round-N-claude.md`; reply with the path and per-severity counts only". The brief forbids it from spawning subagents; if its reply mentions delegating, note it in the report.

**Reviewer B — GPT via omp.** Bash, `run_in_background: true`:

```bash
cd "$TOP" && omp -p --no-session --no-extensions --no-skills \
  --model "$GPT_MODEL" --thinking "$GPT_EFFORT" \
  --tools=read,bash,grep,glob --max-time 30m \
  "$(cat $SKILL_DIR/REVIEWER-BRIEF.md)

The document under review is $OUT/ARCHITECTURE.md. <scope line> Reply with the complete findings file in the format the brief specifies, and nothing else." \
  > "$OUT/reviews/round-N-gpt.md" 2> "$OUT/reviews/round-N-gpt.log"
```

With `--gpt-runner codex`: `codex exec -s read-only --ephemeral -m "$GPT_MODEL" -c model_reasoning_effort="$GPT_EFFORT" -o "$OUT/reviews/round-N-gpt.md" "<same prompt>"` (model id without the provider prefix). If the file carries anything above the `# Findings` header, trim it. Round completes when both files exist and are non-empty; if one is empty, rerun that reviewer once, then proceed and say so.

## Phase 3 — Judge and apply

Do not read the findings files. Spawn one `general-purpose` subagent, the **judge**, with: both findings paths, `$OUT/survey/`, `$OUT/ARCHITECTURE.md`, and these instructions:

> Reviewers are adversaries, not authorities. For every finding, open the cited evidence and rule `accepted` (code agrees with the reviewer — apply the Fix to the survey row named by the map row's `source` column, or add the row to the right survey file), `rejected` (code agrees with the map — cite the proving line), or `unverifiable` (append the claim as a row to `$OUT/open-questions.md`). Write `$OUT/reviews/round-N-disposition.md`: `| reviewer | id | severity | ruling | reason (path:line) |`, one row per finding. Append one line to `$OUT/review-log.md`: `round N — claude: raised/accepted/rejected · gpt: raised/accepted/rejected`. Do not edit ARCHITECTURE.md. Reply with the per-ruling counts and the ids of the three rulings you are least sure of.

Re-run assemble. Spot-check the three named rulings yourself with `grep -n` at the cited lines (≤3 tool calls each); overturn by editing the survey row and the disposition. `cp $OUT/ARCHITECTURE.md $OUT/reviews/ARCHITECTURE.round-N.md`. If rounds remain, return to Phase 2 with a diff-only scope.

## Phase 4 — Diagram

Produce every format named in `--diagram`:

- `excalidraw`: `python3 $SKILL_DIR/scripts/gen_excalidraw.py $OUT/ARCHITECTURE.md $OUT/architecture.excalidraw && python3 -m json.tool $OUT/architecture.excalidraw > /dev/null`.
- `tldraw`: invoke that skill with the §6 Mermaid block as input, write `$OUT/architecture.tldr`.
- `html`: `python3 $SKILL_DIR/scripts/gen_html.py $OUT/ARCHITECTURE.md $OUT/architecture.html`. One self-contained page: the §6 diagram drawn by mermaid.js (loaded from jsDelivr, so viewing needs network) with the §2–§5 tables beneath it. Open with `open $OUT/architecture.html`.

## Report

- Paths: the map, each diagram file produced, `reviews/`.
- Mode, units re-surveyed (incremental), subsystem and edge counts; per round, findings raised / accepted / rejected per reviewer; the three spot-checked rulings and whether you overturned any.
- §7 open questions, in full — these are what the user must decide.
- Whether `$OUT` is tracked by git.

Do not commit or push. Do not delete `reviews/` or `survey/`; the survey files are the map's source and the reviews are its audit trail.
